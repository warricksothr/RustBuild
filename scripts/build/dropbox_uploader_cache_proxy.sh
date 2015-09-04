#!/usr/bin/env bash

#
# This is a script to cache some of the files flowing through dropbox_uploader.sh
#
# The reason behind this script is to minimize the network requests made by the dropbox_uploader
# and to reduce the network bandwidth consumed when requesting the same fail multiple times.
#
# This script doesn't seek to replace or duplicate functionality, but proxy some of the heavier
# actions and pass the rest through to the actual dropbox uploader script transparently
#

# We always want to fail on an error
# This is the safest way to proxy or reallym do anything here
set -e

# Set the default debug to false, unless the environment variable is already set
if [ -z $DEBUG ]; then
  DEBUG=false
fi

# Only enable debugging and halting if we're in debug mode, otherwise we're transparent!
if $DEBUG; then
  set -x
  echo "Proxying Through Transparent Dropbox Uploader Script"
fi

# The dropbox_uploader script that we're going to proxy
: ${DROPBOX:=~/dropbox_uploader.sh}
# Location where we'll store the cached data
: ${CACHE_DIR:=~/.dropbox_uploader_cache}
# The number of seconds to consider the cached items as authoritative
# If the file is older than the lifetime, we'll perform the requested operation
# through the dropbox script and then cache the new results. The default here
# is a week. 60 * 60 * 24 * 7
: ${MAX_LIFETIME:=604800}
# The maximum amount of data we should cache in KiloBytes
# 1,000,000 is ~1GB
: ${MAX_CACHE_SIZE:=1000000}

mkdir -p $CACHE_DIR

# Global array with the real parameters that we care about
# Mostly all of the parameters stripped of the flags and their additional information
declare -a REAL_PARAMETERS_ARRAY
# This is a function to parse out the parameters that we don't care about (Flag parameters)
# So that our proxy doesn't get confused by the flag parameters
get_real_parameters () {
  # Looping through all the parameters
  local filename_expected_next=false
  local index=0
  echo "$@"
  for param in "$@"; do
    if $DEBUG; then echo "Evaluating: [$param]"; fi
    # Recognized flag params that we don't care about
    case $param in 
      # Special case here, this is followed by something that looks normal
      # so we're using a flag to exclude the next item from the results
      -f)
        filename_expected_next=true
        continue
      ;;
      -s|-d|-q|-p|-k) continue;;
      -*|*)
        if $filename_expected_next; then 
          filename_expected_next=false
          continue 
        fi
        REAL_PARAMETERS_ARRAY[$index]=$param
        index=$((index+1))
      ;;
    esac
  done
}

# Function wrapper so that we can disable calls to the script that we're proxying
# Useful for testing, or for doing local only caching with the ability to add
# cloud support at a moments notice
proxy () { 
if [ "$LOCAL_ONLY" != "true" ]; then
  $DROPBOX "$@"
else
  echo "Prevented from calling $DROPBOX $@"
fi
}

# Simple logging function
log () {
  if $DEBUG; then
    echo "$1"
  fi
}

#Parse out the real parmeters that we need to care about
get_real_parameters "$@"

log "The Real Parameters from [$@] are [${REAL_PARAMETERS_ARRAY[@]}]"

# In special cases we'll do our own work on the cache and then pass along the command if necessary
# The first of the real parameters is always going to be the function in the dropbox_upload script
COMMAND=${REAL_PARAMETERS_ARRAY[0]}
case $COMMAND in
  download)
    # Check our cache. If it exists there, copy that file and exit. If it doesn't download it 
    # and then cache it for ourselves.
    # Path of the file we're downloading
    DOWNLOAD=${REAL_PARAMETERS_ARRAY[1]}
    
    # Splitting out parts of the path, to know if we're dealing with a file or directory
    ORIG_IFS="$IFS"
    IFS="/"
    PATH_PARTS=($DOWNLOAD)
    IFS=$ORIG_IFS
    
    # Get the name of our target file/directory
    END_CHAR=$(echo "$DOWNLOAD" | tr -s ' ' | tail -c 2)
    TARGET=${PATH_PARTS[-1]}
    if [ "$END_CHAR" == "/" ]; then
      TARGET="${TARGET}/"
    fi
   
    # If our target file/directory exists in the cache, lets try that
    if [ -e "${CACHE_DIR}/$DOWNLOAD" ]; then
      # Need to parse the name from the path as we can download with path information
      # Also needs to handle when we decide to pull an entire folder. So don't strip a trailing '/'
      # check how old the existing file is
      FILE_MODIFIED_TIME=$(stat -c %Y "${CACHE_DIR}/$DOWNLOAD")
      CURRENT_TIME=$(date +%s)
      AGE=$(((CURRENT_TIME - FILE_MODIFIED_TIME)))
      if [ $AGE -le $MAX_LIFETIME ]; then
        cp -r ${CACHE_DIR}/$DOWNLOAD $TARGET
        # Touch the file to indicate that we have used it recently and it
        # shouldn't be removed from the cache right now
        touch ${CACHE_DIR}/$DOWNLOAD
        # Exit early for flow reasons. Better to avoid extra if's and duplicated code
        exit 0
      fi
    fi

    # Need to make sure the requisite cache directory exists to save to
    if [ ${#PATH_PARTS[@]} -gt 1 ]; then
      PATH_LENGTH=${#PATH_PARTS[@]}
      END_PATH_LENGTH=$(($PATH_LENGTH - 1))
      TARGET_PATH=""
      for ((i=0; i < $END_PATH_LENGTH; i++)); do
        TARGET_PATH="${TARGET_PATH}/${PATH_PARTS[$i]}"
      done
      mkdir -p "${CACHE_DIR}/${TARGET_PATH}"
    fi

    # If the above failed, we'll fall through to here and perform like we would've if the
    # file didn't exist in the cache
    proxy "$@"
    cp -r ${PWD}/$TARGET ${CACHE_DIR}/$DOWNLOAD
  ;;
  upload)
    # Cache the upload and then pass it along to the dropbox script
    proxy "$@"
    UPLOAD=${REAL_PARAMETERS_ARRAY[1]}
    UPLOAD_LOCATION=${REAL_PARAMETERS_ARRAY[2]}
    mkdir -p ${CACHE_DIR}/${UPLOAD_LOCATION}
    cp -r $UPLOAD ${CACHE_DIR}/${UPLOAD_LOCATION}
  ;;
  delete)
    # Delete our locally cached files/directories and then pass the command along to the
    # dropbox script
    proxy "$@"
    # Try to remove the file from cache if it exists, otherwise skip
    rm -r "${CACHE_DIR}/${REAL_PARAMETERS_ARRAY[1]}" || true
  ;;
  mkdir)
    # Create the directory in our cache, and then pass the command along to the dropbox script
    proxy "$@"
    mkdir -p "${CACHE_DIR}/${REAL_PARAMETERS_ARRAY[1]}"
    exit 0
  ;;
  *)
    # Pass anything we don't recognize to the dropbox script so that we're transparent to the user
    proxy "$@"
    exit 0
  ;;
esac

# Clean the cache files in the cache directory until we're below the requested size
clean_cache_oldest () {
  local cache_directory=$1
  local current_size_difference=$2
  # Find a listing of all the files along with their paths in the cache directory
  local files="$(find -L $cache_directory)"
  # Build lists of mtime
  declare -a files_mtime
  for file in $files; do
    # Don't include directories
    if [ ! -d $file ]; then
      # Done by time and then size
      file_mtime+=("$(stat -c %Y "${file}")|$(du -s $file | sed -r 's/([0-9]+)\s.*$/\1/')|${file}")
    fi
  done
  # Print out size and file name, then create a list and sort them
  printf '%s\n' "${file_mtime[@]}" > .cache_file_list
  file_list_sorted=($(cat .cache_file_list | sort -bg))
  rm .cache_file_list
  # Delete files, starting with the oldest, until the desired size is reached
  # Walk through the cache and delete the old files till we no longer need them
  for cache_file_line in ${file_list_sorted[@]}; do
    local line=($(echo $cache_file_line | tr "|" "\n"))
    local size=${line[1]}
    local cache_file=${line[2]}
    log $cache_file
    rm $cache_file
    current_size_difference=$((current_size_difference - size))
    if [ $current_size_difference -ge 0 ]; then
      # Continue till we're below out desired cache size
      continue
    else
      # Exit once we're clear
      break
    fi
  done
}

#Clean the cache if it's over the desired size by deleting the oldest files from the cache first
: ${CURRENT_CACHE_SIZE:="$(du -s $CACHE_DIR | sed -r 's/([0-9]+)\s.*$/\1/')"}
: ${CURRENT_CACHE_VS_MAX:="$((CURRENT_CACHE_SIZE-MAX_CACHE_SIZE))"}

log "Current Cache Size is ${CURRENT_CACHE_SIZE}."
log "The Maximum Cache Size is ${MAX_CACHE_SIZE}."
log "The difference is ${CURRENT_CACHE_VS_MAX}."

clean_cache_oldest $CACHE_DIR $CURRENT_CACHE_VS_MAX

if [ $CURRENT_CACHE_VS_MAX -ge $MAX_CACHE_SIZE ]; then
  log "Cleaning the current cache of the oldest files because it is greater than the max cache size"
  # Clean the oldest files in the cache, till we've cleaned up the required files
  clean_cache_oldest $CACHE_DIR $CURRENT_CACHE_VS_MAX
fi

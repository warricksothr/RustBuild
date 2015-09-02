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

#Parse out the real parmeters that we need to care about
get_real_parameters "$@"

if $DEBUG; then
  echo "The Real Parameters from [$@] are [${REAL_PARAMETERS_ARRAY[@]}]"
fi

# In special cases we'll do our own work on the cache and then pass along the command if necessary
# The first of the real parameters is always going to be the function in the dropbox_upload script
COMMAND=${REAL_PARAMETERS_ARRAY[0]}
case $COMMAND in
  download)
  # Check our cache. If it exists there, copy that file and exit. If it doesn't download it 
  # and then cache it for ourselves.
  DOWNLOAD=${REAL_PARAMETERS_ARRAY[1]}
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
  if [ -e "${CACHE_DIR}/$DOWNLOAD" ]; then
    # Need to parse the name from the path as we can download with path information
    # Also needs to handle when we decide to pull an entire folder. So don't strip a trailing '/'
    # check how old the existing file is
    FILE_MODIFIED_TIME=$(stat -c %Y "${CACHE_DIR}/$DOWNLOAD")
    CURRENT_TIME=$(date +%s)
    AGE=$(((CURRENT_TIME - FILE_MODIFIED_TIME)))
    if [ $AGE -le $MAX_LIFETIME ]; then
      cp -r ${CACHE_DIR}/$DOWNLOAD $TARGET
      # Exit early for flow reasons. Better to avoid extra if's and duplicated code
      exit 0
    fi
  fi
  # Need to make sure the requisite cache directory exists to save to
  if [ ${#PATH_PARTS[@]} -gt 1 ]; then
    PATH_LENGTH=${#PATH_PARTS[@]}
    END_PATH_LENGTH=$(($PATH_LENGTH - 2))
    TARGET_PATH=""
    for i in "seq $END_PATH_ELEMENT"; do
      TARGET_PATH="${TARGET_PATH}/${PATH_PARTS[$i]}"
    done
    mkdir -p "${CACHE_DIR}/${TARGET_PATH}"
  fi
  #echo $PWD
  proxy "$@"
  cp -r ${PWD}/$TARGET ${CACHE_DIR}/$DOWNLOAD
  ;;
  upload)
  # Cache the upload and then pass it along to the dropbox script
  proxy "$@"
  UPLOAD=${REAL_PARAMETERS_ARRAY[1]}
  UPLOAD_LOCATION=${REAL_PARAMETERS_ARRAY[2]}
  cp -r $UPLOAD ${CACHE_DIR}/${UPLOAD_LOCATION}
  ;;
  delete)
  # Delete our locally cached files/directories and then pass the command along to the
  # dropbox script
  proxy "$@"
  rm -r "${CACHE_DIR}/${REAL_PARAMETERS_ARRAY[1]}"
  ;;
  mkdir)
  # Create the directory in our cache, and then pass the command along to the dropbox script
  proxy "$@"
  mkdir -p "${CACHE_DIR}/${REAL_PARAMETERS_ARRAY[1]}"
  ;;
  *)
  # Pass anything we don't recognize to the dropbox script so that we're transparent to the user
  proxy "$@"
  ;;
esac

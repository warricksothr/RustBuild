#!/usr/bin/env bash

#
# Script file with common functions for usage by all build scripts
#

set -x
set -e

# If TTYtter is installed, we can use it to tweet a status to the configured
# account. If no account is configured, then we'll just ignore this request
tweet_status() {
    if [ -f "$HOME/.ttytterkey" ]; then
        ttytter -ssl -status="$1"
    fi
}

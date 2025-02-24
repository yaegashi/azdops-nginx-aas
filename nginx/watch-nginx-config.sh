#!/bin/bash

hash_dir() {
    find $1 -follow -type f -exec md5sum {} + | sort -k 2 | md5sum
}

WATCH_DIR=$1
PREVIOUS_HASH=$(hash_dir $WATCH_DIR)

while true; do
    CURRENT_HASH=$(hash_dir $WATCH_DIR)
    if test "$CURRENT_HASH" != "$PREVIOUS_HASH"; then
        echo "Change detected in $WATCH_DIR"
        /docker-entrypoint.d/20-envsubst-on-templates.sh
        nginx -s reload
        PREVIOUS_HASH=$CURRENT_HASH
    fi
    sleep 10
done

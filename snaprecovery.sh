#!/bin/sh
#
# by Siddharth Dushantha
#

# Colored log indicators
GOOD="\033[92;1m[✔]\033[0m"
BAD="\033[91;1m[✘]\033[0m"
INFO="\033[94;1m[I]\033[0m"
RUNNING="\033[37;1m[~]\033[0m"
NOTICE="\033[93;1m[!]\033[0m"

usage(){
cat <<EOF
usage: snaprecovery [-n, --no-merge]

Options:
    -n, --no-merge    don't merge videos with their respective overlays
EOF
    exit 1
}

# Determines whether or not to merge videos with overlays. Must be unset or null/empty to disable.
MERGE=yes

while [ "$1" ] ; do
    case $1 in
        -h|--help) usage ;;
        -n|--no-merge) unset MERGE ;;
    esac
    shift
done

SNAPS_DIRECTORY="snaps_output"

for DEPENDENCY in awk ${MERGE:+ffmpeg stat touch}; do
    if ! command -v "$DEPENDENCY" >/dev/null 2>&1; then
        printf "%b Could not find '%s', is it installed?\n" "$BAD" "$DEPENDENCY"
        exit 1
    fi
done


if su -c cp -rp /data/user/0/com.snapchat.android/files/file_manager/chat_snap/ .tmp; then
  su -c chown -R "$USER":"$USER" .tmp
  # via ssh it work without this but directly from termux it fail so i keep it even if it's less secure
  su -c chmod -R 777 .tmp 
else
  printf "%b %b\n" "$BAD" "Error. this script probably doesn't have acess to snapchat's storage."
  exit 1
fi

mkdir -p "$SNAPS_DIRECTORY"
TOTAL_FILES=$(find .tmp | wc -l)
COUNT=1

# If MERGE is unset, rename all files without merging
if [ -z "${MERGE:+x}" ]; then
    for SNAP in .tmp/*.chat_snap.[012]; do
        EXTENSION=$(file --mime-type -b "$SNAP" | sed 's/.*\///g')
        NEW_FILENAME="${SNAP%chat_snap.[012]}$EXTENSION"

        # \r            Move cursor to the start of the current line
        # \e[2K         Clear whole line
        printf "\r\033[2K%b Recovering [%d/%d]: %s" "$RUNNING" "$COUNT" "$TOTAL_FILES" "$NEW_FILENAME"
        mv "$SNAP" "$NEW_FILENAME"
        COUNT=$((COUNT + 1))
    done
    rm -f .tmp/*.json
else # If MERGE is set, rename singletons and merge overlays
    # For files without overlays, rename with the correct extension
    for SNAP in .tmp/*.chat_snap.0; do
        EXTENSION=$(file --mime-type -b "$SNAP" | sed 's/.*\///g')
        NEW_FILENAME="${SNAP%chat_snap.0}$EXTENSION"

        # \r            Move cursor to the start of the current line
        # \e[2K         Clear whole line
        printf "\r\033[2K%b Recovering [%d/%d]: %s" "$RUNNING" "$COUNT" "$TOTAL_FILES" "$NEW_FILENAME"
        mv "$SNAP" "$NEW_FILENAME"
        COUNT=$((COUNT + 1))
    done

    # For files with overlays, use ffmpeg to merge the overlay
    for SNAP in .tmp/*.chat_snap.1; do
        BASE="$SNAP"
        OVERLAY="${SNAP%1}2"
        NEW_FILENAME="${SNAP%.chat_snap.1}.merged.mkv"

        # if <name>.chat_snap.2 doesn't exist, don't attempt to merge anything
        [ -f "$OVERLAY" ] || continue

        # \r            Move cursor to the start of the current line
        # \e[2K         Clear whole line
        printf "\r\033[2K%b Recovering [%d/%d]: %s" "$RUNNING" "$COUNT" "$TOTAL_FILES" "$NEW_FILENAME"
        
        # merge overlay onto video
        ffmpeg -loglevel quiet -i "$BASE" -i "$OVERLAY" -filter_complex '[1:v][0:v]scale2ref[overlay][base]; [base][overlay]overlay' -c:a copy "$NEW_FILENAME"

        # adjust timestamp of new merged video to match base video
        TIMESTAMP="$(stat --format=%Y "$BASE")"
        touch -d "@$TIMESTAMP" "$NEW_FILENAME"

        # remove base, overlay, and unused JSON
        rm -f "$BASE" "$OVERLAY" "${SNAP%chat_snap.1}json"

        COUNT=$((COUNT + 1))
    done
fi

printf "\r\033[2K%b Recovered %d snaps\n" "$GOOD" "$TOTAL_FILES"
printf "%b The recovered snaps can be found in '%s'\n" "$NOTICE" "$SNAPS_DIRECTORY"

mv .tmp/* "$SNAPS_DIRECTORY"
rm -rf .tmp/


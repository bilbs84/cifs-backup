#!/bin/bash
# backup-and-sync.sh

CFG_FILE=/etc/config.ini
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

# Set the working directory
WORK_DIR="/usr/local/bin"
cd "$WORK_DIR" || exit

# Function to log to Docker logs
log() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "${GREEN}${TIMESTAMP}${NC} - $@" | tee -a /proc/1/fd/1
}

# Function to log errors to Docker logs with timestamp
log_error() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    while read -r line; do
        echo "${YELLOW}${TIMESTAMP}${NC} - ERROR - $line" | tee -a /proc/1/fd/1
    done
}

# Check if the script is run as superuser
if [[ $EUID -ne 0 ]]; then
   log_error <<< "This script must be run as root"
   exit 1
fi

# Function to read the configuration file
read_config() {
    local section=$1
    eval "$(awk -F "=" -v section="$section" '
        BEGIN { in_section=0; exclusions="" }
        /^\[/{ in_section=0 }
        $0 ~ "\\["section"\\]" { in_section=1; next }
        in_section && !/^#/ && $1 {
            gsub(/^ +| +$/, "", $1)
            gsub(/^ +| +$/, "", $2)
            if ($1 == "exclude") {
                exclusions = exclusions "--exclude=" $2 " "
            } else {
                print $1 "=\"" $2 "\""
            }
        }
        END { print "exclusions=\"" exclusions "\"" }
    ' $CFG_FILE)"
}

# Function to mount the CIFS share
mount_cifs() {
    local mount_point=$1
    local server=$2
    local share=$3
    local user=$4
    local password=$5

    mkdir -p "$mount_point" 2> >(log_error)
    mount -t cifs -o username="$user",password="$password",vers=3.0 //"$server"/"$share" "$mount_point" 2> >(log_error)
}

# Function to unmount the CIFS share
unmount_cifs() {
    local mount_point=$1
    umount "$mount_point" 2> >(log_error)
}

# Function to check if the CIFS share is mounted
is_mounted() {
    local mount_point=$1
    mountpoint -q "$mount_point"
}

# Function to handle backup and sync
handle_backup_sync() {
    local section=$1
    local source_dir=$2
    local mount_point=$3
    local exclusions=$4
    local compress=$5
    local keep_days=$6

    if [ "$compress" -eq 1 ]; then
        # Create a timestamp for the backup filename
        TIMESTAMP=$(date +%d-%m-%Y-%H.%M)
        mkdir -p "${mount_point}/${section}"
        BACKUP_FILE="${mount_point}/${section}/${section}-${TIMESTAMP}.tar.gz"
        log "tar -czvf $BACKUP_FILE -C $source_dir $exclusions . 2> >(log_error)"
        tar -czvf "$BACKUP_FILE" -C "$source_dir" $exclusions . 2> >(log_error)
    else
        rsync_cmd=(rsync -av --inplace --delete $exclusions "$source_dir/" "$mount_point/${section}/")
        log "${rsync_cmd[@]}"
        "${rsync_cmd[@]}" 2> >(log_error)
    fi

    # Delete compressed backups older than specified days
    find "$mount_point/$section" -type f -name "${section}-*.tar.gz" -mtime +${keep_days} -exec rm {} \; 2> >(log_error)
}

LOCK_FILE="/tmp/$1.lock"

section=$1

if [[ -n "$section" ]]; then
    log "Running backup for section: $section"
    (
        flock -n 200 || {
            log "Another script is already running. Exiting."
            exit 1
        }

        read_config "$section"

        # Set default values for missing fields
        : ${server:=""}
        : ${share:=""}
        : ${user:=""}
        : ${password:=""}
        : ${source:=""}
        : ${compress:=0}
        : ${exclusions:=""}
        : ${keep:=3}

        MOUNT_POINT="/mnt/$section"

        if [[ -z "$server" || -z "$share" || -z "$user" || -z "$password" || -z "$source" ]]; then
            log "Skipping section $section due to missing required fields."
            exit 1
        fi

        log "Processing section: $section"
        mount_cifs "$MOUNT_POINT" "$server" "$share" "$user" "$password"

        if is_mounted "$MOUNT_POINT"; then
            log "CIFS share is mounted for section: $section"
            handle_backup_sync "$section" "$source" "$MOUNT_POINT" "$exclusions" "$compress" "$keep"
            unmount_cifs "$MOUNT_POINT"
            log "Backup and sync finished for section: $section"
        else
            log "Failed to mount CIFS share for section: $section"
        fi
) 200>"$LOCK_FILE"
else
    log "No section specified. Exiting."
    exit 1
fi

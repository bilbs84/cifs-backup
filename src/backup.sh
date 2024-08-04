#!/bin/bash
# backup-and-sync.sh

CFG_FILE=/etc/config.ini
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"
WORK_DIR="/usr/local/bin"
SECTION=$1
LOCK_FILE="/tmp/$SECTION.lock"

# Set the working directory
#cd "$WORK_DIR" || exit

# Function to log to Docker logs
log() {
    printf -v timeStamp '%(%Y-%m-%d %H:%M:%S)T'
    echo -e "${GREEN}${timeStamp}${NC} - $@" | tee -a /proc/1/fd/1
}

# Function to log errors to Docker logs with timestamp
log_error() {
    printf -v timeStamp '%(%Y-%m-%d %H:%M:%S)T'
    while read -r line; do
        echo -e "${YELLOW}${timeStamp}${NC} - ERROR - $line" | tee -a /proc/1/fd/1
    done
}

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
    local \
        mountPoint=$1 \
        server=$2 \
        share=$3 \
        user=$4 \
        password=$5

    mkdir -p "$mountPoint" 2> >(log_error)
    mount -t cifs -o username="$user",password="$password",vers=3.0 //"$server"/"$share" "$mountPoint" 2> >(log_error)
}

# Function to unmount the CIFS share
unmount_cifs() {
    local mountPoint=$1
    umount "$mountPoint" 2> >(log_error)
}

# Function to check if the CIFS share is mounted
is_mounted() {
    local mountPoint=$1
    mountpoint -q "$mountPoint"
}

# Function to handle backup and sync
handle_backup_sync() {
    local \
        section=$1 \
        sourceDir=$2 \
        mountPoint=$3 \
        subfolderName=$4 \
        exclusions=$5 \
        compress=$6 \
        keep_days=$7 \
        server=$8 \
        share=$9 \

    if [ "$compress" -eq 1 ]; then
        # Create a timestamp for the backup filename
        timeStamp=$(date +%d-%m-%Y-%H.%M)
        mkdir -p "${mountPoint}/${subfolderName}"
        backupFile="${mountPoint}/${subfolderName}/${section}-${timeStamp}.tar.gz"
        #log "tar -czvf $backupFile -C $sourceDir $exclusions . 2> >(log_error)"
        log "Creating archive of ${sourceDir}" 
        tar -czvf "$backupFile" -C "$sourceDir" $exclusions . 2> >(log_error)
        log "//${server}/${share}/${subfolderName}/${section}-${timeStamp}.tar.gz was successfuly created."
    else
        rsync_cmd=(rsync -av --inplace --delete $exclusions "$sourceDir/" "$mountPoint/${subfolderName}/")
        #log "${rsync_cmd[@]}"
        log "Creating a backup of ${sourceDir}"
        "${rsync_cmd[@]}" 2> >(log_error)
        log "Successful backup located in //${server}/${share}/${subfolderName}."
    fi

    # Delete compressed backups older than specified days
    find "$mountPoint/$subfolderName" -type f -name "${section}-*.tar.gz" -mtime +${keep_days} -exec rm {} \; 2> >(log_error)
}

# Check if the script is run as superuser
if [[ $EUID -ne 0 ]]; then
   log_error <<< "This script must be run as root"
   exit 1
fi

# Main script functions
if [[ -n "$SECTION" ]]; then
    log "Running backup for section: $SECTION"
    (
        flock -n 200 || {
            log "Another script is already running. Exiting."
            exit 1
        }

        read_config "$SECTION"

        # Set default values for missing fields
        : ${server:=""}
        : ${share:=""}
        : ${user:=""}
        : ${password:=""}
        : ${source:=""}
        : ${compress:=0}
        : ${exclusions:=""}
        : ${keep:=3}
        : ${subfolderName:=$SECTION}  # Will implement in a future release
        
        MOUNT_POINT="/mnt/$SECTION"
        
        if [[ -z "$server" || -z "$share" || -z "$user" || -z "$password" || -z "$source" ]]; then
            log "Skipping section $SECTION due to missing required fields."
            exit 1
        fi

        log "Processing section: $SECTION"
        mount_cifs "$MOUNT_POINT" "$server" "$share" "$user" "$password"

        if is_mounted "$MOUNT_POINT"; then
            log "CIFS share is mounted for section: $SECTION"
            handle_backup_sync "$SECTION" "$source" "$MOUNT_POINT" "$subfolderName" "$exclusions" "$compress" "$keep" "$server" "$share"
            unmount_cifs "$MOUNT_POINT"
            log "Backup and sync finished for section: $SECTION"
        else
            log "Failed to mount CIFS share for section: $SECTION"
        fi
) 200>"$LOCK_FILE"
else
    log "No section specified. Exiting."
    exit 1
fi

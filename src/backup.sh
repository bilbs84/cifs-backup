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

# Function to convert bytes to human-readable format
bytesHuman() {
    local \
        bytes=$1 \
        kib=$((bytes/1024)) \
        mib=$((kib/1024)) \
        gib=$((mib/1024))

    if (( gib > 0 )); then
        echo "${gib}G"
    elif (( mib > 0 )); then
        echo "${mib}M"
    elif (( kib > 0 )); then
        echo "${kib}K"
    else
        echo "${bytes}B"
    fi
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
        keepDays=$7 \
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
        # Delete compressed backups older than specified days
        log "Checking for, and removing any backups older than ${keepDays} days old"
        oldFiles=$(find "${mountPoint}/${subfolderName}" -type f -name "${section}-*.tar.gz" -mtime +${keepDays})
        if [[ -n "$oldFiles" ]]; then
            log "Found files for ${section} older than ${keepDays} days, removing files..."
            log "$oldFiles"

            find "${mountPoint}/${subfolderName}" -type f -name "${section}-*.tar.gz" -mtime +${keepDays} -exec rm {} \; 2> >(log_error)
        else
            log "No files older than ${keepDays} days found."
        fi
        
    else
        rsync_cmd=(rsync -av --inplace --delete $exclusions "${sourceDir}/" "${mountPoint}/${subfolderName}/")
        log "Creating a backup of ${sourceDir}"

        # Capture the rsync output
        rsync_output=$("${rsync_cmd[@]}" 2> >(log_error))

        # Log the output for debugging purposes
        log "$rsync_output"

        # Extract the total bytes transferred
        bytesTransferred=$(echo "$rsync_output" | grep 'sent' | awk '{print $2}')

        bytesHuman=$(bytesHuman "$bytesTransferred")

        # Log the successful backup and the total bytes transferred
        log "Successful backup located in //${server}/${share}/${subfolderName}."
        log "Total bytes transferred: $bytesHuman"
    fi

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

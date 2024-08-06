#!/bin/bash
# cifs-backup.sh

cfgFile=/etc/config.yaml
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"
SECTION=$1
lockFile="/tmp/$SECTION.lock"

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

# Function to log critical errors to Docker logs with timestamp
log_critical() {
    printf -v timeStamp '%(%Y-%m-%d %H:%M:%S)T'
    while read -r line; do
        echo -e "${RED}${timeStamp}${NC} - CRITICAL - $line" | tee -a /proc/1/fd/1
    done
}

# Function to read the configuration file
read_config() {
    local section=$1
    server=$(yq e ".$section.server" $cfgFile)
    share=$(yq e ".$section.share" $cfgFile)
    user=$(yq e ".$section.user" $cfgFile)
    passwd=$(yq e ".$section.passwd" $cfgFile)
    source=$(yq e ".$section.source" $cfgFile)
    compress=$(yq e ".$section.compress" $cfgFile)
    schedule=$(yq e ".$section.schedule" $cfgFile)
    subfolder=$(yq e ".$section.subfolder" $cfgFile)
    exclude=$(yq e ".$section.exclude[]" $cfgFile)
    exclusions=""
    if [[ -n $exclude ]]; then
        while IFS= read -r e; do
            exclusions="${exclusions} --exclude ${e}"
        done <<< "$exclude"
    fi
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
    local bytes=$(echo "$1" | tr -d ',') \
    local kib mib gib

    kib=$(echo "scale=2; $bytes / 1024" | bc)
    mib=$(echo "scale=2; $kib / 1024" | bc)
    gib=$(echo "scale=2; $mib / 1024" | bc)

    if (( $(echo "$gib >= 1" | bc -l) )); then
        echo "${gib}G"
    elif (( $(echo "$mib >= 1" | bc -l) )); then
        echo "${mib}M"
    elif (( $(echo "$kib >= 1" | bc -l) )); then
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
        subfolder=$4 \
        exclusions=$5 \
        compress=$6 \
        keepDays=$7 \
        server=$8 \
        share=$9 \

    if [ "$compress" -eq 1 ]; then
        # Create a timestamp for the backup filename
        timeStamp=$(date +%d-%m-%Y-%H.%M)
        mkdir -p "${mountPoint}/${subfolder}"
        backupFile="${mountPoint}/${subfolder}/${section}-${timeStamp}.tar.gz"
        log "Creating archive of ${sourceDir}"
        tar -czvf "$backupFile" -C "$sourceDir" $exclusions . 2> >(log_error)

        # Check if the tar command was successful
        if [ $? -eq 0 ]; then
            # Get the file size of the compressed archive
            fileSize=$(stat -c%s "$backupFile")
            fileSizeHuman=$(bytesHuman "$fileSize")

            log "//${server}/${share}/${subfolder}/${section}-${timeStamp}.tar.gz was successfully created."
            log "Total size of the compressed archive: $fileSizeHuman"
        else
            log_error "Failed to create the archive."
        fi

        # Delete compressed backups older than specified days
        log "Checking for, and removing any backups older than ${keepDays} days old"
        oldFiles=$(find "${mountPoint}/${subfolder}" -type f -name "${section}-*.tar.gz" -mtime +${keepDays})
        if [[ -n "$oldFiles" ]]; then
            log "Found files for ${section} older than ${keepDays} days, removing files..."
            log "$oldFiles"

            find "${mountPoint}/${subfolder}" -type f -name "${section}-*.tar.gz" -mtime +${keepDays} -exec rm {} \; 2> >(log_error)
        else
            log "No files older than ${keepDays} days found."
        fi

    else
        rsync_cmd=(rsync -av --inplace --delete $exclusions "${sourceDir}/" "${mountPoint}/${subfolder}/")
        log "Creating a backup of ${sourceDir}"

        # Capture the rsync output
        rsync_output=$("${rsync_cmd[@]}" 2> >(log_error))

        # Extract the total bytes transferred
        bytesTransferred=$(echo "$rsync_output" | grep 'sent' | awk '{print $2}')

        # Convert the bytesTransferred into a human readable format
        bytesHuman=$(bytesHuman "$bytesTransferred")

        # Log the successful backup and the total bytes transferred
        log "Successful backup located in //${server}/${share}/${subfolder}."

        # Display the total amount of data transferred
        log "Total bytes transferred: $bytesHuman"
    fi

}

# Check if the script is run as superuser
if [[ $EUID -ne 0 ]]; then
   log_error <<< "This script must be run as root"
   exit 1
fi

# Main script functions
if [[ -n "$section" ]]; then
    log "Running backup for section: $section"
    (
        flock -n 200 || {
            log "Another script is already running. Exiting."
            exit 1
        }

        log "$section"
        read_config "$section"

        # Set default values for missing fields
        : ${server:=""}
        : ${share:=""}
        : ${user:=""}
        : ${passwd:=""}
        : ${source:=""}
        : ${compress:=0}
        : ${exclusions:=""}
        : ${keep:=3}
        : ${subfolder:=$section}  # Will implement in a future release

       mountPoint="/mnt/$section"

        if [[ -z "$server" || -z "$share" || -z "$user" || -z "$passwd" || -z "$source" ]]; then
            log "Skipping section $section due to missing required fields."
            exit 1
        fi

        log "Processing section: $section"
        mount_cifs "$mountPoint" "$server" "$share" "$user" "$passwd"

        if is_mounted "$mountPoint"; then
            if touch "$mountPoint/test" 2>/dev/null; then
                rm "$mountPoint/test"
                log "CIFS share is mounted for section: $section"
                handle_backup_sync "$section" "$source" "$mountPoint" "$subfolder" "$exclusions" "$compress" "$keep" "$server" "$share"
                unmount_cifs "$mountPoint"
                log "Backup and sync finished for section: $section"
            else
                log_critical "$mountPoint not writable, exiting..."
                exit 1
            fi
        else
            log "Failed to mount CIFS share for section: $section"
        fi
) 200>"$lockFile"
else
    log "No section specified. Exiting."
    exit 1
fi
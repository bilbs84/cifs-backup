#!/bin/bash
# entry.sh

cfgFile=/etc/config.yaml
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"
error_file=$(mktemp)
cronConfig=$(mktemp)
share=""
source=""
compress=""
schedule=""
subfolder=""

# Function to log to Docker logs
log() {
    printf -v timeStamp '%(%Y-%m-%d %H:%M:%S)T'
    echo -e "${GREEN}${timeStamp}${NC} - $@"
}

# Function to log errors to Docker logs with timestamp
log_error() {
    printf -v timeStamp '%(%Y-%m-%d %H:%M:%S)T'
    while read -r line; do
        echo -e "${YELLOW}${timeStamp}${NC} - ERROR - $line" | tee -a /proc/1/fd/1
    done
}

# Function to syncronise the timezone
set_tz() {
    if [ -n "$TZ" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
        echo $TZ > /etc/timezone
        ln -snf /usr/share/zoneinfo$TZ /etc/localtime
        log "Setting timezone to ${TZ}"
    else
        log_error <<< "Invalid or unset TZ variable: $TZ"
    fi
}

# Function to check the mountpoint
check_mount() {
    local mount_point=$1
    if ! mountpoint -q "$mount_point"; then
        log_error <<< "CIFS share is not mounted at $mount_point"
        exit 1
    fi
}

mount_cifs() {
    local \
        mount_point=$1 \
        user=$2 \
        password=$3 \
        server=$4 \
        share=$5

    mkdir -p "$mount_point" 2> >(log_error)
    mount -t cifs -o username="$user",password="$password",vers=3.0 //"$server"/"$share" "$mount_point" 2> >(log_error)
}

# Create or clear the crontab file
sync_cron() {
    local \
        configStart="###CIFS_BACKUP CONFIG###" \
        configEnd="###END CONFIG###"

    # Read current cron configuration into a temporary file
    crontab -l > $cronConfig 2> "$error_file"

    # Check and log any errors with readin in configuration
    if [ -s "$error_file" ]; then
        log_error <<< "$(cat "$error_file")"
        rm "$error_file"
        : > $cronConfig
    else
        rm "$error_file"
    fi

    # Remove any previous configuration entries that we made
    sed -i "/$configStart/,/$configEnd/d" "$cronConfig"

    # Add start marker for configuration
    echo "$configStart" >> $cronConfig

    # Loop through each section and add the cron job
    for sec in $(yq e 'keys' $cfgFile | tr -d ' -'); do
        read_config "$sec"
        if [[ -n "$schedule" ]]; then
            echo "$schedule /usr/local/bin/cifs-backup.sh $sec" >> $cronConfig
        fi
    done

    # Add end marker for configuration
    echo "$configEnd" >> $cronConfig
}

read_config() {
    section=$1
    server=$(yq e ".$section.server" $cfgFile)
    share=$(yq e ".$section.share" $cfgFile)
    source=$(yq e ".$section.source" $cfgFile)
    compress=$(yq e ".$section.compress" $cfgFile)
    schedule=$(yq e ".$section.schedule" $cfgFile)
    subfolder=$(yq e ".$section.subfolder" $cfgFile)
}

# Set the timezone as defined by Environmental variable
set_tz

# Install the new crontab file
sync_cron
crontab "$cronConfig" 2> >(log_error)
rm "$cronConfig" 2> >(log_error)

# Ensure cron log file exists
touch /var/log/cron.log 2> >(log_error)

# Start cron
log "Starting cron service..."
cron 2> >(log_error) && log "Cron started successfully"

# Check if cron is running
if ! pgrep cron > /dev/null; then
  log "Cron is not running."
  exit 1
else
  log "Cron is running."
fi

# Check if the CIFS shares are mountable
log "Checking all shares are mountable"

echo $jobs
for sec in $(yq e 'keys' $cfgFile | tr -d ' -'); do
    log "Reading config for $sec"
    read_config "$sec"
    mountPoint="/mnt/$sec"
    # mount_cifs "$mountPoint" "$user" "$passwd" "$server" "$share"
    # check_mount "$mountPoint"
    log "${sec}: //${server}/${share} successfuly mounted at $mountPoint... Unmounting"
    umount "$mountPoint" 2> >(log_error)
done
log "All shares mounted successfuly.  Starting cifs-backup"

# Print a message indicating we are about to tail the log
log "Tailing the cron log to keep the container running"
tail -f /var/log/cron.log
log "cifs-backup now running"
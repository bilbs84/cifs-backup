#!/bin/bash
# entry.sh

CFG_FILE=/etc/config.ini
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"
error_file=$(mktemp)
WORK_DIR="/usr/local/bin"

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
                if ($1 == "schedule") {
                    # Escape double quotes and backslashes
                    gsub(/"/, "\\\"", $2)
                }
                print $1 "=\"" $2 "\""
            }
        }
        END { print "exclusions=\"" exclusions "\"" }
    ' $CFG_FILE)"
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
    local mount_point=$1
    local user=$2
    local password=$3
    local server=$4
    local share=$5

    mkdir -p "$mount_point" 2> >(log_error)
    mount -t cifs -o username="$user",password="$password",vers=3.0 //"$server"/"$share" "$mount_point" 2> >(log_error)
}

# Create or clear the crontab file
sync_cron() {
    crontab -l > mycron 2> "$error_file"

    if [ -s "$error_file" ]; then
        log_error <<< "$(cat "$error_file")"
        rm "$error_file"
        : > mycron
    else
        rm "$error_file"
    fi

    # Loop through each section and add the cron job
    for section in $(awk -F '[][]' '/\[[^]]+\]/{print $2}' $CFG_FILE); do
        read_config "$section"
        if [[ -n "$schedule" ]]; then
            echo "$schedule /usr/local/bin/backup.sh $section" >> mycron
        fi
    done
}

# Set the working directory
cd "$WORK_DIR" || exit

# Set the timezone as defined by Environmental variable
set_tz

# Install the new crontab file
sync_cron
crontab mycron 2> >(log_error)
rm mycron 2> >(log_error)

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
for section in $(awk -F '[][]' '/\[[^]]+\]/{print $2}' $CFG_FILE); do
    read_config "$section"
    MOUNT_POINT="/mnt/$section"
    mount_cifs "$MOUNT_POINT" "$user" "$password" "$server" "$share"
    check_mount "$MOUNT_POINT"
    log "$section: //$server/$share succesfully mounted at $MOUNT_POINT... Unmounting"
    umount "$MOUNT_POINT" 2> >(log_error)
done
log "All shares mounted successfuly.  Starting cifs-backup"

# Print a message indicating we are about to tail the log
log "Tailing the cron log to keep the container running"
tail -f /var/log/cron.log
log "cifs-backup now running"

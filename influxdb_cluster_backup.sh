#!/bin/bash

# === Configurations ===

# Path to the directory where backups will be stored
BACKUP_DIR="/path/to/backup"
LOG_FILE="/path/to/backup/backup.log"  # Path to the log file
RETENTION_DAYS=7  # Backups older than this will be deleted

DATE=$(date +"%Y%m%d")  # Date format
TIME=$(date +"%H%M%S")
SITENAME="your-sitename"  # Set the site name
META_BACKUP_DIR=$(mktemp -d "$BACKUP_DIR/meta_${DATE}_${TIME}_XXXXXX")  # Temp dir for meta backup
DATA_BACKUP_DIR=$(mktemp -d "$BACKUP_DIR/data_${DATE}_${TIME}_XXXXXX")  # Temp dir for data backup
META_ARCHIVE_NAME="meta-${SITENAME}-${DATE}.tar.gz"  # Name for the meta archive
DATA_ARCHIVE_NAME="data-${SITENAME}-${DATE}.tar.gz"  # Name for the data archive

# List of TCP addresses of data nodes (modify as needed)
DATA_NODES=("tcp://data-node1:8088" "tcp://data-node2:8088")

# Telegram API information (recommended to set these as environment variables for security)
BOT_TOKEN="${BOT_TOKEN:-your-bot-token}"  # Replace with your bot token
CHAT_ID="${CHAT_ID:-your-chat-id}"      # Replace with your chat ID

# === Functions ===

# Logging function to write both to the console and a log file
log_message() {
    local message=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
}

# Function to send a message to Telegram
send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$message" > /dev/null
    
    if [ $? -ne 0 ]; then
        log_message "Warning: Failed to send Telegram message."
    fi
}

# Function to check the execution status and stop the script if there's an error
check_command_status() {
    if [ $? -ne 0 ]; then
        send_telegram_message "Error: $1 failed!"
        log_message "Error: $1 failed!"
        cleanup
        exit 1
    fi
}

# Function to calculate and log backup size
calculate_backup_size() {
    local archive=$1
    local size=$(du -sh "$archive" | cut -f1)
    log_message "Backup size of $archive: $size"
    send_telegram_message "Backup size of $archive: $size"
}

# Function to clean up temporary directories
cleanup() {
    log_message "Cleaning up temporary directories..."
    rm -rf "$META_BACKUP_DIR" "$DATA_BACKUP_DIR"
}

# Set a trap to clean up if the script is interrupted (SIGINT, SIGTERM)
trap cleanup EXIT

# Function to enforce backup retention policy
enforce_retention_policy() {
    log_message "Enforcing retention policy..."
    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm -f {} \;
    log_message "Removed backups older than $RETENTION_DAYS days."
}

# === Main Script ===

log_message "Starting backup process for site $SITENAME..."

# 1. Backup Meta Nodes
log_message "Backing up Meta Nodes for site $SITENAME..."
influxd-ctl backup -strategy=only-meta "$META_BACKUP_DIR"
check_command_status "Meta Nodes Backup"

# Compress the meta backup using tar with the specified name
cd "$BACKUP_DIR"
tar -czf "$META_ARCHIVE_NAME" -C "$META_BACKUP_DIR" .
check_command_status "Compress Meta Backup"
calculate_backup_size "$META_ARCHIVE_NAME"

# 2. Backup Data Nodes
for NODE in "${DATA_NODES[@]}"; do
    log_message "Backing up Data Node: $NODE for site $SITENAME..."
    influxd-ctl backup -strategy=incremental -from "$NODE" "$DATA_BACKUP_DIR"
    check_command_status "Data Node Backup $NODE"
done

# Compress the data backup using tar
tar -czf "$DATA_ARCHIVE_NAME" -C "$DATA_BACKUP_DIR" .
check_command_status "Compress Data Backup"
calculate_backup_size "$DATA_ARCHIVE_NAME"

# 3. Completion and Cleanup
log_message "Backup successful for site $SITENAME. Files are stored in $BACKUP_DIR."
send_telegram_message "Backup successful for site $SITENAME. Files are stored in $BACKUP_DIR."

# Enforce retention policy
enforce_retention_policy

# Clean up will happen via the trap
log_message "Backup process for site $SITENAME completed successfully!"

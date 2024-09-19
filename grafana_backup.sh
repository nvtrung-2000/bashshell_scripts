#!/bin/bash

set -euo pipefail

SITE_NAME="MTS"
IP_ADDRESS=$(hostname -I | awk '{print $1}')
BACKUP_DIR="/backup/grafana-backups/"
GRAFANA_PATHS=("/etc/grafana/" "/var/lib/grafana/" "/var/log/grafana/")
DATE=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="${SITE_NAME}-grafana-${IP_ADDRESS}-${DATE}.tar.gz"
TELEGRAM_CHATID=""
TELEGRAM_TOKEN=""
TELEGRAM_API_URL="https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"
LOG_FILE="/var/log/grafana_backups/grafana_backup.log"

exec > >(tee -a ${LOG_FILE}) 2>&1

function check_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi
}

function check_grafana_paths() {
    for path in "${GRAFANA_PATHS[@]}"; do
        if [ ! -d "$path" ]; then
            printf "Warning: %s does not exist, skipping...\n" "$path" >&2
            GRAFANA_PATHS=("${GRAFANA_PATHS[@]/$path}")
        fi
    done
}

function delete_old_backups() {
    printf "Deleting old backups...\n"
    local old_files=($(find "$BACKUP_DIR" -type f -mtime +15 -name "*.tar.gz"))
    local num_files_deleted=0
    local deleted_files=()

    if [[ ${#old_files[@]} -gt 0 ]]; then
        for file in "${old_files[@]}"; do
            rm -f "$file"
            deleted_files+=("$file")
            ((num_files_deleted++))
        done
        printf "Deleted %d old backup files.\n" "$num_files_deleted"
    else
        printf "No old backup files found.\n"
    fi

    if [[ "$num_files_deleted" -gt 0 ]]; then
        send_telegram_delete_message "$num_files_deleted" "${deleted_files[@]}"
    else
        send_telegram_delete_message 0
    fi
}

function send_telegram_message() {
    local filesize; filesize=$(du -sh "${BACKUP_DIR}${BACKUP_FILE}" | awk '{print $1}')
    local message="*BACKUP NOTIFICATION:*
    - Backup thành công tại *${SITE_NAME}* - \`${IP_ADDRESS}\`
    - Đường dẫn lưu trữ: \`${BACKUP_DIR}${BACKUP_FILE}\` [${filesize}]
    - Thời gian backup: \`$(date)\`"

    if ! curl -s -X POST "${TELEGRAM_API_URL}" -d chat_id="${TELEGRAM_CHATID}" -d text="$message" -d parse_mode="Markdown"; then
        printf "Error sending Telegram message!\n" >&2
        return 1
    fi
    printf "Telegram message sent successfully.\n"
}

function send_telegram_delete_message() {
    local deleted_count="$1"
    shift
    local deleted_files=("${@:-}")

    local message
    if [[ "$deleted_count" -gt 0 ]]; then
        message="*DELETE NOTIFICATION:*
        - Đã xóa thành công \`${deleted_count}\` file backup cũ tại *${SITE_NAME}* - \`${IP_ADDRESS}\`.
        - Tên file bị xoá: \`$(printf "%s\n" "${deleted_files[@]}" | paste -sd ", ")\`
        - Thời gian: \`$(date)\`"
    else
        message="*DELETE NOTIFICATION:*
        - Không có file backup cũ nào để xóa tại *${SITE_NAME}* - \`${IP_ADDRESS}\`.
        - Thời gian: \`$(date)\`"
    fi

    if ! curl -s -X POST "${TELEGRAM_API_URL}" -d chat_id="${TELEGRAM_CHATID}" -d text="$message" -d parse_mode="Markdown"; then
        printf "Error sending Telegram delete message!\n" >&2
        return 1
    fi
    printf "Telegram delete message sent successfully.\n"
}

function send_telegram_restart_message() {
    local message="*SERVICE NOTIFICATION:*
    - Dịch vụ Grafana tại *${SITE_NAME}* - \`${IP_ADDRESS}\` đã được khởi động lại thành công.
    - Thời gian khởi động lại: \`$(date)\`"

    if ! curl -s -X POST "${TELEGRAM_API_URL}" -d chat_id="${TELEGRAM_CHATID}" -d text="$message" -d parse_mode="Markdown"; then
        printf "Error sending Telegram restart message!\n" >&2
        return 1
    fi
    printf "Telegram restart message sent successfully.\n"
}

function create_backup() {
    printf "Creating backup...\n"
    tar -czf "${BACKUP_DIR}${BACKUP_FILE}" "${GRAFANA_PATHS[@]}"
    printf "Backup created successfully: %s\n" "${BACKUP_FILE}"
}

function stop_grafana() {
    printf "Stopping Grafana service...\n"
    systemctl stop grafana-server || {
        printf "Failed to stop Grafana service!\n" >&2
        return 1
    }
    printf "Grafana service stopped successfully.\n"
}

function start_grafana() {
    printf "Starting Grafana service...\n"
    systemctl start grafana-server
    if systemctl is-active --quiet grafana-server; then
        printf "Grafana service started successfully.\n"
        send_telegram_restart_message
    else
        printf "Failed to start Grafana service!\n" >&2
        return 1
    fi
}

function main() {
    check_backup_dir
    check_grafana_paths
    delete_old_backups
    stop_grafana
    create_backup
    start_grafana
    send_telegram_message
}

main

#!/bin/bash

# Đường dẫn tới thư mục lưu trữ bản sao lưu
BACKUP_DIR="/path/to/backup"
DATE=$(date +"%Y%m%d")  # Định dạng ngày yêu cầu
TIME=$(date +"%H%M%S")
SITENAME="your-sitename"  # Đặt tên cho site
META_BACKUP_DIR="$BACKUP_DIR/meta_$DATE_$TIME"
DATA_BACKUP_DIR="$BACKUP_DIR/data_$DATE_$TIME"
META_ARCHIVE_NAME="meta-${SITENAME}-${DATE}.tar.gz"  # Tên file nén meta
DATA_ARCHIVE_NAME="data-${SITENAME}-${DATE}.tar.gz"  # Tên file nén data

# Danh sách địa chỉ TCP của các data node (chỉnh sửa cho phù hợp)
DATA_NODES=("tcp://data-node1:8088" "tcp://data-node2:8088")

# Thông tin Telegram API
BOT_TOKEN="your-bot-token"  # Thay bằng bot token của bạn
CHAT_ID="your-chat-id"      # Thay bằng chat ID của bạn

# Biến lưu trữ thông báo
TELEGRAM_MESSAGE="Sao lưu cho site *${SITENAME}* vào ngày $DATE $TIME:\n"

# Hàm gửi thông báo tới Telegram
send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" > /dev/null
}

# Tạo thư mục backup nếu chưa tồn tại
mkdir -p "$META_BACKUP_DIR" "$DATA_BACKUP_DIR"

# Hàm để kiểm tra kết quả thực thi và dừng script nếu có lỗi
check_command_status() {
    if [ $? -ne 0 ]; then
        TELEGRAM_MESSAGE+="Lỗi: $1 thất bại!\n"
        send_telegram_message "$TELEGRAM_MESSAGE"
        echo "Lỗi: $1 thất bại!" >&2
        exit 1
    fi
}

# 1. Sao lưu Meta Nodes
echo "Sao lưu Meta Nodes cho site $SITENAME..."
influxd-ctl backup -strategy=only-meta "$META_BACKUP_DIR"
check_command_status "Sao lưu Meta Nodes"
TELEGRAM_MESSAGE+="Sao lưu Meta Nodes thành công!\n"

# Nén meta backup với tên theo yêu cầu bằng tar
cd "$BACKUP_DIR"
tar -czf "$META_ARCHIVE_NAME" -C "$META_BACKUP_DIR" .
check_command_status "Nén Meta Backup"
TELEGRAM_MESSAGE+="Đã nén Meta Backup thành công với tên file: $META_ARCHIVE_NAME\n"

# 2. Sao lưu Data Nodes
for NODE in "${DATA_NODES[@]}"; do
    echo "Sao lưu Data Node: $NODE cho site $SITENAME..."
    influxd-ctl backup -strategy=incremental -from "$NODE" "$DATA_BACKUP_DIR"
    check_command_status "Sao lưu Data Node $NODE"
    TELEGRAM_MESSAGE+="Sao lưu Data Node $NODE thành công!\n"
done

# Nén data backup bằng tar
cd "$BACKUP_DIR"
tar -czf "$DATA_ARCHIVE_NAME" -C "$DATA_BACKUP_DIR" .
check_command_status "Nén Data Backup"
TELEGRAM_MESSAGE+="Đã nén Data Backup thành công với tên file: $DATA_ARCHIVE_NAME\n"

# 3. Hoàn thành
TELEGRAM_MESSAGE+="Quá trình sao lưu cho site *${SITENAME}* hoàn thành thành công!"
send_telegram_message "$TELEGRAM_MESSAGE"

echo "Quá trình sao lưu cho site $SITENAME hoàn thành thành công!"

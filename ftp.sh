#!/bin/bash
CONFIG_FILE="web.txt"
DOWNLOAD_DIR="./web"

[ ! -f "$CONFIG_FILE" ] && echo "配置文件不存在" && exit 1

if ! command -v 7z &> /dev/null; then
    echo "正在安装 7z..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y p7zip-full >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y p7zip p7zip-plugins >/dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        dnf install -y p7zip p7zip-plugins >/dev/null 2>&1
    elif command -v apk &> /dev/null; then
        apk add --no-cache p7zip >/dev/null 2>&1
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm p7zip >/dev/null 2>&1
    fi
fi

if ! command -v lftp &> /dev/null; then
    echo "正在安装 lftp..."
    if command -v apt-get &> /dev/null; then
        apt-get install -y lftp >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y lftp >/dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        dnf install -y lftp >/dev/null 2>&1
    elif command -v apk &> /dev/null; then
        apk add --no-cache lftp >/dev/null 2>&1
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm lftp >/dev/null 2>&1
    fi
fi

if ! command -v mysqldump &> /dev/null; then
    echo "正在安装 mysqldump..."
    if command -v apt-get &> /dev/null; then
        apt-get install -y mysql-client >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y mysql >/dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        dnf install -y mysql >/dev/null 2>&1
    elif command -v apk &> /dev/null; then
        apk add --no-cache mysql-client >/dev/null 2>&1
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm mysql-clients >/dev/null 2>&1
    fi
fi

backup_site() {
    local FTP_HOST=$1
    local FTP_USER=$2
    local FTP_PASS=$3
    local FTP_REMOTE=$4
    local DB_HOST=$5
    local DB_NAME=$6
    local DB_USER=$7
    local DB_PASS=$8
    local NAME=$9
    
    local DIR="$DOWNLOAD_DIR/$NAME"
    local ARCHIVE="${NAME}.7z"
    
    mkdir -p "$DIR"
    
    if [ -n "$FTP_HOST" ]; then
        echo "[$NAME] 开始下载FTP..."
        
        lftp -c "
        set ftp:ssl-allow no
        set ftp:passive-mode on
        set mirror:parallel-transfer-count 6
        set net:connection-limit 6
        set net:max-retries 5
        set net:timeout 30
        open -u $FTP_USER,$FTP_PASS $FTP_HOST
        mirror --parallel=6 --no-perms --no-umask $FTP_REMOTE $DIR
        bye
        "
        
        while pgrep -f "lftp.*$FTP_HOST" >/dev/null 2>&1; do
            sleep 2
        done
        
        local FTP_COUNT=$(find "$DIR" -type f 2>/dev/null | wc -l)
        echo "[$NAME] FTP下载完成: $FTP_COUNT 文件"
    fi
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_NAME" ]; then
        echo "[$NAME] 开始备份数据库..."
        
        mysqldump -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$DIR/${DB_NAME}.sql" 2>/dev/null
        
        if [ -f "$DIR/${DB_NAME}.sql" ]; then
            local DB_SIZE=$(du -h "$DIR/${DB_NAME}.sql" | cut -f1)
            echo "[$NAME] 数据库备份完成: $DB_SIZE"
        else
            echo "[$NAME] 数据库备份失败"
        fi
    fi
    
    local TOTAL_COUNT=$(find "$DIR" -type f 2>/dev/null | wc -l)
    
    if [ $TOTAL_COUNT -eq 0 ]; then
        echo "[$NAME] 备份失败: 无内容"
        rm -rf "$DIR"
        return 1
    fi
    
    echo "[$NAME] 开始压缩..."
    
    7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on "$ARCHIVE" "$DIR" >/dev/null 2>&1
    
    if [ -f "$ARCHIVE" ]; then
        local SIZE=$(du -h "$ARCHIVE" | cut -f1)
        echo "[$NAME] 完成: $SIZE"
        rm -rf "$DIR"
    else
        echo "[$NAME] 压缩失败"
    fi
}

export -f backup_site
export DOWNLOAD_DIR

while IFS='|' read -r FTP_HOST FTP_USER FTP_PASS FTP_REMOTE DB_HOST DB_NAME DB_USER DB_PASS NAME; do
    [[ -z "$NAME" || "$FTP_HOST" =~ ^#.*$ || "$FTP_HOST" =~ ^[[:space:]]*$ && "$DB_HOST" =~ ^[[:space:]]*$ ]] && continue
    [[ "$NAME" =~ ^#.*$ ]] && continue
    [ -z "$FTP_HOST" ] && [ -z "$DB_HOST" ] && continue
    backup_site "$FTP_HOST" "$FTP_USER" "$FTP_PASS" "$FTP_REMOTE" "$DB_HOST" "$DB_NAME" "$DB_USER" "$DB_PASS" "$NAME" &
done < "$CONFIG_FILE"

wait
[ -d "$DOWNLOAD_DIR" ] && rmdir "$DOWNLOAD_DIR" 2>/dev/null
echo "全部完成"

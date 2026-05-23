#!/usr/bin/env bash

CONFIG_FILE="ftp.txt"
DOWNLOAD_DIR="./web"

[ ! -f "$CONFIG_FILE" ] && echo "配置文件不存在" && exit 1

mkdir -p "$DOWNLOAD_DIR"

if ! command -v 7z &> /dev/null; then
    echo "安装 7z..."
    sudo apt-get update -qq
    sudo apt-get install -y p7zip-full
fi

if ! command -v lftp &> /dev/null; then
    echo "安装 lftp..."
    sudo apt-get install -y lftp
fi

if ! command -v mysqldump &> /dev/null; then
    echo "安装 mysql-client..."
    sudo apt-get install -y mysql-client
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
    local ARCHIVE="$DOWNLOAD_DIR/${NAME}.7z"

    mkdir -p "$DIR"

    if [ -n "$FTP_HOST" ]; then

        echo "[$NAME] 下载 FTP..."

        lftp -c "
        set ftp:ssl-allow no
        set ftp:passive-mode on
        open -u $FTP_USER,$FTP_PASS $FTP_HOST
        mirror --parallel=6 --no-perms --no-umask $FTP_REMOTE $DIR
        bye
        "

    fi

    if [ -n "$DB_HOST" ] && [ -n "$DB_NAME" ]; then

        echo "[$NAME] 导出数据库..."

        mysqldump \
          -h"$DB_HOST" \
          -u"$DB_USER" \
          -p"$DB_PASS" \
          "$DB_NAME" \
          > "$DIR/${DB_NAME}.sql"

    fi

    COUNT=$(find "$DIR" -type f | wc -l)

    if [ "$COUNT" -eq 0 ]; then
        echo "[$NAME] 没有文件"
        rm -rf "$DIR"
        return
    fi

    echo "[$NAME] 压缩..."

    7z a \
      -t7z \
      -mx=9 \
      "$ARCHIVE" \
      "$DIR" \
      >/dev/null

    if [ -f "$ARCHIVE" ]; then
        echo "[$NAME] 完成"
        rm -rf "$DIR"
    else
        echo "[$NAME] 压缩失败"
    fi
}

export -f backup_site
export DOWNLOAD_DIR

while IFS='|' read -r FTP_HOST FTP_USER FTP_PASS FTP_REMOTE DB_HOST DB_NAME DB_USER DB_PASS NAME
do

    [[ -z "$NAME" ]] && continue
    [[ "$NAME" =~ ^# ]] && continue

    backup_site \
      "$FTP_HOST" \
      "$FTP_USER" \
      "$FTP_PASS" \
      "$FTP_REMOTE" \
      "$DB_HOST" \
      "$DB_NAME" \
      "$DB_USER" \
      "$DB_PASS" \
      "$NAME" &

done < "$CONFIG_FILE"

wait

echo "全部完成"

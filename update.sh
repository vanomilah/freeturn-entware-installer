#!/bin/sh

echo "====================================================="
echo "  🔄 Обновление FreeTurn-server"
echo "====================================================="

# 1. Проверяем текущую архитектуру
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)        FT_ARCH="amd64" ;;
    aarch64|arm64) FT_ARCH="arm64" ;;
    armv7l|armv8l) FT_ARCH="armv7" ;;
    mips)          FT_ARCH="mips" ;;
    mipsle|mipsel) FT_ARCH="mipsle" ;;
    *)             echo "❌ Неизвестная архитектура $ARCH"; exit 1 ;;
esac

# 2. Узнаем последнюю версию
API_URL="https://api.github.com/repos/samosvalishe/free-turn-proxy/releases/latest"
LATEST_VERSION=$(curl -s "$API_URL" | grep '"tag_name":' | awk -F '"' '{print $4}')

if [ -z "$LATEST_VERSION" ]; then
    echo "❌ Ошибка получения версии с GitHub. Проверь интернет."
    exit 1
fi

echo "📢 Найдена версия: $LATEST_VERSION"

# 3. Скачиваем бинарник
FILE_NAME="server-linux-${FT_ARCH}"
DOWNLOAD_URL="https://github.com/samosvalishe/free-turn-proxy/releases/download/${LATEST_VERSION}/${FILE_NAME}"

echo "⬇️ Скачивание обновления..."
wget -qO /opt/bin/freeturn-server.tmp "$DOWNLOAD_URL"

if [ -s "/opt/bin/freeturn-server.tmp" ]; then
    # 4. Останавливаем службу, подменяем файл, запускаем
    echo "🚀 Установка обновления..."
    /opt/etc/init.d/S99vk-turn-server stop
    
    mv -f /opt/bin/freeturn-server.tmp /opt/bin/freeturn-server
    chmod +x /opt/bin/freeturn-server
    
    /opt/etc/init.d/S99vk-turn-server start
    echo "✅ Обновление до $LATEST_VERSION успешно завершено!"
else
    echo "❌ Ошибка скачивания обновления!"
    rm -f /opt/bin/freeturn-server.tmp
    exit 1
fi

#!/bin/sh

echo "====================================================="
echo "  🔄 Обновление клиента FreeTurn"
echo "====================================================="

echo "🔍 Определение архитектуры..."
ENTWARE_ARCH=$(opkg print-architecture | awk '{print $2}' | grep -v 'all' | head -n 1)

if echo "$ENTWARE_ARCH" | grep -q "mipsel"; then FT_ARCH="mipsle-softfloat"
elif echo "$ENTWARE_ARCH" | grep -q "mips"; then FT_ARCH="mips-softfloat"
elif echo "$ENTWARE_ARCH" | grep -q "aarch64\|arm64"; then FT_ARCH="arm64"
elif echo "$ENTWARE_ARCH" | grep -q "armv7"; then FT_ARCH="armv7"
elif echo "$ENTWARE_ARCH" | grep -q "x86_64"; then FT_ARCH="amd64"
else FT_ARCH="amd64"; fi

echo "✅ Архитектура: $FT_ARCH"

echo "🌐 Поиск последней версии на GitHub..."
API_URL="https://api.github.com/repos/samosvalishe/free-turn-proxy/releases/latest"
LATEST_VERSION=$(curl -4 -kLs "$API_URL" | grep '"tag_name":' | awk -F '"' '{print $4}')

if [ -z "$LATEST_VERSION" ]; then
    echo "⚠️ Не удалось получить версию по API. Используем v1.7.2 по умолчанию."
    LATEST_VERSION="v1.7.2"
else
    echo "🚀 Найдена актуальная версия: $LATEST_VERSION"
fi

FILE_NAME="client-linux-${FT_ARCH}"
DOWNLOAD_URL="https://github.com/samosvalishe/free-turn-proxy/releases/download/${LATEST_VERSION}/${FILE_NAME}"

echo "⬇️ Скачивание обновления..."
# Качаем во временную папку, чтобы не сломать текущий рабочий процесс
curl -4 -kL -o /tmp/freeturn-client-new "$DOWNLOAD_URL"

if [ -s "/tmp/freeturn-client-new" ]; then
    echo "🛑 Остановка текущей службы..."
    /opt/etc/init.d/S98vk-turn-client stop > /dev/null 2>&1
    
    echo "📦 Установка новой версии..."
    mv /tmp/freeturn-client-new /opt/bin/freeturn-client
    chmod +x /opt/bin/freeturn-client
    
    echo "🔄 Запуск службы..."
    /opt/etc/init.d/S98vk-turn-client start > /dev/null 2>&1
    
    echo "====================================================="
    echo "🎉 Клиент успешно обновлен до версии $LATEST_VERSION!"
    echo "Ваши настройки и конфиги WireGuard остались нетронутыми."
    echo "====================================================="
else
    echo "❌ Ошибка скачивания обновления! Файл не найден или сеть недоступна."
    rm -f /tmp/freeturn-client-new
    exit 1
fi

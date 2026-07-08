#!/bin/sh

echo "====================================================="
echo "  🚀 Автоматическая установка FreeTurn + Web Generator"
echo "====================================================="

# --- 1. Установка базовых пакетов ---
echo "📦 Обновляем пакеты и устанавливаем веб-сервер..."
opkg update > /dev/null
opkg install lighttpd lighttpd-mod-cgi wget curl > /dev/null

# --- 2. Определение архитектуры и загрузка сервера ---
echo "🔍 Определение архитектуры процессора..."
ARCH=$(uname -m)

case "$ARCH" in
    x86_64)        FT_ARCH="amd64" ;;
    aarch64|arm64) FT_ARCH="arm64" ;;
    armv7l|armv8l) FT_ARCH="armv7" ;;
    mips)          FT_ARCH="mips" ;;
    mipsle|mipsel) FT_ARCH="mipsle" ;;
    *)             echo "❌ Ошибка: неизвестная архитектура $ARCH"; exit 1 ;;
esac

echo "✅ Архитектура: $FT_ARCH"

echo "🔍 Поиск последней версии сервера на GitHub..."
API_URL="https://api.github.com/repos/samosvalishe/free-turn-proxy/releases/latest"
LATEST_VERSION=$(curl -s "$API_URL" | grep '"tag_name":' | awk -F '"' '{print $4}')

if [ -z "$LATEST_VERSION" ]; then
    echo "⚠️ Не удалось получить версию по API. Используем v1.7.2 по умолчанию."
    LATEST_VERSION="v1.7.2"
fi

# Точное имя файла, как на скриншоте (например, server-linux-arm64)
FILE_NAME="server-linux-${FT_ARCH}"
DOWNLOAD_URL="https://github.com/samosvalishe/free-turn-proxy/releases/download/${LATEST_VERSION}/${FILE_NAME}"

echo "⬇️ Скачивание ${FILE_NAME} (версия ${LATEST_VERSION})..."
# Качаем напрямую в папку bin
wget -qO /opt/bin/freeturn-server "$DOWNLOAD_URL"

if [ -s "/opt/bin/freeturn-server" ]; then
    echo "✅ Сервер успешно скачан!"
    chmod +x /opt/bin/freeturn-server
else
    echo "❌ Ошибка скачивания бинарника! (Не найден $FILE_NAME)"
    rm -f /opt/bin/freeturn-server
    exit 1
fi

# --- 3. Генерация ключей и IP ---
FT_PORT="56000"
FT_OBF="rtpopus"

echo "⏳ Генерация криптографического ключа обфускации..."
FT_KEY=$(hexdump -v -e '/1 "%02x"' -n 32 /dev/urandom)

echo "🌍 Определение внешнего IP-адреса..."
EXTERNAL_IP=$(wget -qO- http://api.ipify.org 2>/dev/null)
if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP="YOUR_EXTERNAL_IP"
    echo "⚠️ Не удалось определить внешний IP (подставлена заглушка)."
else
    echo "✅ Внешний IP: $EXTERNAL_IP"
fi

# --- 4. Настройка FreeTurn сервера ---
echo "⚙️ Создание стартового скрипта FreeTurn..."
cat << EOF > /opt/etc/init.d/S99vk-turn-server
#!/bin/sh

ENABLED=yes
PROCS=freeturn-server
ARGS="-connect 127.0.0.1:51820 -listen 0.0.0.0:$FT_PORT -obf-profile $FT_OBF -obf-key $FT_KEY"
PIDFILE=/opt/var/run/freeturn-server.pid

. /opt/etc/init.d/rc.func
EOF

chmod +x /opt/etc/init.d/S99vk-turn-server
sed -i 's/\r$//' /opt/etc/init.d/S99vk-turn-server

# --- 5. Настройка Web-сервера ---
mkdir -p /opt/share/www

CGI_CONF="/opt/etc/lighttpd/conf.d/30-cgi.conf"
if [ -f "$CGI_CONF" ]; then
    echo "🔧 Настройка интерпретатора /bin/sh для CGI..."
    sed -i 's|".cgi" => "/opt/bin/perl"|".cgi" => "/bin/sh"|g' "$CGI_CONF"
fi

# --- 6. Развертывание Web-генератора ---
echo "🌐 Создание генератора ссылок..."

cat << 'INSTALL_EOF' > /opt/share/www/generator.cgi
#!/bin/sh
export PATH="/opt/sbin:/opt/bin:/sbin:/bin:/usr/sbin:/usr/bin"

CONFIG_FILE="/opt/etc/init.d/S99vk-turn-server"

if [ -f "$CONFIG_FILE" ]; then
    FT_PORT=$(sed -n 's/.*-listen [^:]*:\([0-9]*\).*/\1/p' "$CONFIG_FILE")
    FT_OBF=$(sed -n 's/.*-obf-profile \([^ "]*\).*/\1/p' "$CONFIG_FILE")
    FT_KEY=$(sed -n 's/.*-obf-key \([^ "]*\).*/\1/p' "$CONFIG_FILE")
else
    FT_PORT="56000"
    FT_KEY="ОШИБКА"
    FT_OBF="rtpopus"
fi

FT_PROVIDER="vk"
FT_MTU="1376"
FT_IP="REPLACE_ME_IP"

echo "Content-type: text/html; charset=utf-8"
echo ""

cat << HTML_EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dynamic FreeTurn WG Link Generator</title>
    <style>
        body { font-family: sans-serif; padding: 20px; max-width: 600px; margin: auto; background: #f0f2f5; }
        .container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .row { display: flex; gap: 10px; margin-top: 10px; }
        .col { flex: 1; }
        label { display: block; font-size: 13px; font-weight: bold; margin-bottom: 4px; color: #333; }
        input, textarea { width: 100%; padding: 8px; box-sizing: border-box; border: 1px solid #ccc; border-radius: 4px; font-family: monospace; }
        textarea { height: 180px; resize: vertical; white-space: pre; }
        button { margin-top: 20px; padding: 12px; width: 100%; background: #007bff; color: white; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
        button:hover { background: #0056b3; }
        .result { margin-top: 20px; padding: 15px; background: #eef; border: 1px solid #ccd; border-radius: 4px; word-break: break-all; }
        .copy-btn { margin-top: 10px; background: #28a745; font-size: 14px; padding: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>FreeTurn WG Generator</h2>
        <div class="row">
            <div class="col"><label>Version (v)</label><input type="number" id="v" value="1"></div>
            <div class="col"><label>Provider</label><input type="text" id="provider" value="\$FT_PROVIDER"></div>
            <div class="col"><label>MTU</label><input type="number" id="mtu" value="\$FT_MTU"></div>
        </div>
        <div class="row">
            <div class="col"><label>Peer (IP:Port)</label><input type="text" id="peer" value="\$FT_IP:\$FT_PORT"></div>
            <div class="col"><label>Obfuscation (obf)</label><input type="text" id="obf" value="\$FT_OBF"></div>
        </div>
        <div class="row">
            <div class="col"><label>Key</label><input type="text" id="key" value="\$FT_KEY"></div>
        </div>
        <div style="margin-top: 15px;">
            <label>WireGuard Config (wg)</label>
            <textarea id="wg" placeholder="Вставь сюда конфиг клиента WireGuard..."></textarea>
        </div>
        <button onclick="generateLink()">Сгенерировать ссылку</button>
        <div class="result" id="resultBox" style="display: none;">
            <strong>Готовая ссылка:</strong><br><br>
            <span id="outputLink"></span>
            <button class="copy-btn" onclick="copyLink()">Скопировать в буфер</button>
        </div>
    </div>
    <script>
        function generateLink() {
            const config = { v: parseInt(document.getElementById('v').value), provider: document.getElementById('provider').value, peer: document.getElementById('peer').value, obf: document.getElementById('obf').value, key: document.getElementById('key').value, mtu: parseInt(document.getElementById('mtu').value), wg: document.getElementById('wg').value.trim() };
            const jsonString = JSON.stringify(config);
            const encodedData = btoa(unescape(encodeURIComponent(jsonString))).replace(/=+$/, '');
            document.getElementById('outputLink').innerText = "freeturn://" + encodedData;
            document.getElementById('resultBox').style.display = 'block';
        }
        function copyLink() {
            const linkText = document.getElementById('outputLink').innerText;
            const textArea = document.createElement("textarea");
            textArea.value = linkText; textArea.style.position = "fixed"; document.body.appendChild(textArea); textArea.focus(); textArea.select();
            try { document.execCommand('copy'); alert("Ссылка скопирована!"); } catch (err) { alert("Ошибка копирования"); } document.body.removeChild(textArea);
        }
    </script>
</body>
</html>
HTML_EOF
INSTALL_EOF

# Подставляем реальный IP
sed -i "s/REPLACE_ME_IP/$EXTERNAL_IP/g" /opt/share/www/generator.cgi

chmod +x /opt/share/www/generator.cgi
sed -i 's/\r$//' /opt/share/www/generator.cgi

# --- 7. Запуск ---
echo "🔄 Перезапуск служб..."
killall lighttpd 2>/dev/null
sleep 1
/opt/etc/init.d/S80lighttpd start
/opt/etc/init.d/S99vk-turn-server restart

# Пытаемся получить локальный IP (br0)
LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -n 1)
fi

echo "====================================================="
echo "🎉 Установка успешно завершена!"
echo "👉 Ваш генератор ссылок доступен по адресу:"
echo "   http://${LAN_IP:-192.168.1.1}:8088/generator.cgi"
echo "====================================================="

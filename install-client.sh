#!/bin/sh

echo "====================================================="
echo "  🛡️ Автоматическая установка клиента FreeTurn + GUI"
echo "====================================================="

echo "📝 Вставьте ссылку freeturn:// и нажмите Enter:"
read FT_LINK

if ! echo "$FT_LINK" | grep -q "^freeturn://"; then
    echo "❌ Ошибка: Неверный формат ссылки!"
    exit 1
fi

echo "📞 Вставьте ссылку на звонок VK (https://vk.com/call/join/...) и нажмите Enter:"
read VK_LINK

if [ -z "$VK_LINK" ]; then
    echo "❌ Ошибка: Ссылка на звонок не может быть пустой!"
    exit 1
fi

B64_DATA=$(echo "$FT_LINK" | sed 's|freeturn://||')
DECODED_JSON=$(echo "$B64_DATA" | awk '{ padding = 4 - length($0) % 4; if (padding < 4) for (i=0; i<padding; i++) $0 = $0 "="; print }' | base64 -d 2>/dev/null)

PEER=$(echo "$DECODED_JSON" | sed -n 's/.*"peer":"\([^"]*\)".*/\1/p')
OBF=$(echo "$DECODED_JSON" | sed -n 's/.*"obf":"\([^"]*\)".*/\1/p')
KEY=$(echo "$DECODED_JSON" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')
WG_CONFIG=$(echo "$DECODED_JSON" | sed -n 's/.*"wg":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')

if [ -z "$PEER" ] || [ -z "$KEY" ]; then
    echo "❌ Ошибка: Не удалось расшифровать параметры."
    exit 1
fi

echo "✅ Подключение к $PEER (Профиль: $OBF)"

if [ ! -z "$WG_CONFIG" ]; then
    echo "-----------------------------------------------------"
    echo "📋 Ваш конфиг WireGuard (скопируйте его):"
    echo "-----------------------------------------------------"
    echo "$WG_CONFIG"
    echo "-----------------------------------------------------"
fi

echo "📦 Установка клиента и локального веб-сервера..."
opkg update > /dev/null
opkg install lighttpd lighttpd-mod-cgi wget-ssl ca-bundle curl > /dev/null

echo "🔍 Определение архитектуры..."
ENTWARE_ARCH=$(opkg print-architecture | awk '{print $2}' | grep -v 'all' | head -n 1)

if echo "$ENTWARE_ARCH" | grep -q "mipsel"; then FT_ARCH="mipsle-softfloat"
elif echo "$ENTWARE_ARCH" | grep -q "mips"; then FT_ARCH="mips-softfloat"
elif echo "$ENTWARE_ARCH" | grep -q "aarch64\|arm64"; then FT_ARCH="arm64"
elif echo "$ENTWARE_ARCH" | grep -q "armv7"; then FT_ARCH="armv7"
elif echo "$ENTWARE_ARCH" | grep -q "x86_64"; then FT_ARCH="amd64"
else FT_ARCH="amd64"; fi

API_URL="https://api.github.com/repos/samosvalishe/free-turn-proxy/releases/latest"
LATEST_VERSION=$(curl -4 -kLs "$API_URL" | grep '"tag_name":' | awk -F '"' '{print $4}')
[ -z "$LATEST_VERSION" ] && LATEST_VERSION="v1.7.2"

FILE_NAME="client-linux-${FT_ARCH}"
DOWNLOAD_URL="https://github.com/samosvalishe/free-turn-proxy/releases/download/${LATEST_VERSION}/${FILE_NAME}"

echo "⬇️ Скачивание ${FILE_NAME}..."
curl -4 -kL -o /opt/bin/freeturn-client "$DOWNLOAD_URL"

if [ -s "/opt/bin/freeturn-client" ]; then
    chmod +x /opt/bin/freeturn-client
else
    echo "❌ Ошибка скачивания клиентского бинарника!"
    exit 1
fi

echo "⚙️ Настройка конфигурации..."
cat << EOF > /opt/etc/init.d/S98vk-turn-client
#!/bin/sh

ENABLED=yes
PROCS=freeturn-client
ARGS="-connect $PEER -vk-link '$VK_LINK' -listen 127.0.0.1:51820 -obf-profile $OBF -obf-key $KEY"
PIDFILE=/opt/var/run/freeturn-client.pid

. /opt/etc/init.d/rc.func
EOF

chmod 755 /opt/etc
chmod 755 /opt/etc/init.d
chmod 755 /opt/etc/init.d/S98vk-turn-client
sed -i 's/\r$//' /opt/etc/init.d/S98vk-turn-client

# --- Настройка локального Web-UI клиента (порт 8089) ---
echo "🌐 Создание веб-интерфейса обновления..."
CGI_CONF="/opt/etc/lighttpd/conf.d/30-cgi.conf"
if [ -f "$CGI_CONF" ]; then
    sed -i 's|".cgi" => "/opt/bin/perl"|".cgi" => "/bin/sh"|g' "$CGI_CONF"
    sed -i 's|#include "conf.d/30-cgi.conf"|include "conf.d/30-cgi.conf"|g' /opt/etc/lighttpd/lighttpd.conf
    sed -i '/server.port/d' /opt/etc/lighttpd/lighttpd.conf
    echo 'server.port = 8089' >> /opt/etc/lighttpd/lighttpd.conf
fi

mkdir -p /opt/share/www
cat << 'CLIENT_CGI_EOF' > /opt/share/www/client.cgi
#!/bin/sh
export PATH="/opt/sbin:/opt/bin:/sbin:/bin:/usr/sbin:/usr/bin"
export LANG=C.UTF-8

CONFIG="/opt/etc/init.d/S98vk-turn-client"

if [ "$REQUEST_METHOD" = "POST" ]; then
    read -n "$CONTENT_LENGTH" POST_DATA
    
    NEW_PEER=$(echo "$POST_DATA" | sed -n 's/.*peer=\([^&]*\).*/\1/p' | sed 's/%3A/:/g')
    NEW_OBF=$(echo "$POST_DATA" | sed -n 's/.*obf=\([^&]*\).*/\1/p' | sed 's/+/ /g;s/%//g')
    NEW_KEY=$(echo "$POST_DATA" | sed -n 's/.*key=\([^&]*\).*/\1/p')
    # Декодируем URL для ссылки VK
    NEW_VK_LINK=$(echo "$POST_DATA" | sed -n 's/.*vk_link=\([^&]*\).*/\1/p' | sed 's/%3A/:/g;s/%2F/\//g;s/%3F/?/g;s/%3D/=/g;s/%26/\&/g')
    
    if [ -f "$CONFIG" ]; then
        [ ! -z "$NEW_PEER" ] && sed -i "s|-connect [^ ]*|-connect $NEW_PEER|g" "$CONFIG"
        [ ! -z "$NEW_OBF" ] && sed -i "s|-obf-profile [^ ]*|-obf-profile $NEW_OBF|g" "$CONFIG"
        [ ! -z "$NEW_KEY" ] && sed -i "s|-obf-key [^ \"\n]*|-obf-key $NEW_KEY|g" "$CONFIG"
        [ ! -z "$NEW_VK_LINK" ] && sed -i "s|-vk-link '[^']*'|-vk-link '$NEW_VK_LINK'|g" "$CONFIG"
        
        /opt/etc/init.d/S98vk-turn-client restart > /dev/null 2>&1
    fi
    
    echo "Status: 303 See Other"
    echo "Location: client.cgi?success=1"
    echo ""
    exit 0
fi

if [ -f "$CONFIG" ]; then
    CUR_PEER=$(sed -n 's/.*-connect \([^ ]*\).*/\1/p' "$CONFIG")
    CUR_OBF=$(sed -n 's/.*-obf-profile \([^ ]*\).*/\1/p' "$CONFIG")
    CUR_VK_LINK=$(sed -n "s/.*-vk-link '\([^']*\)'.*/\1/p" "$CONFIG")
else
    CUR_PEER="Неизвестно"
    CUR_OBF="Неизвестно"
    CUR_VK_LINK=""
fi

echo "Content-type: text/html; charset=utf-8"
echo "Cache-Control: no-cache"
echo ""

cat << HTML_EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Обновление FreeTurn Client</title>
    <style>
        body { font-family: sans-serif; padding: 20px; max-width: 550px; margin: auto; background: #f0f2f5; }
        .container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        label { display: block; font-size: 13px; font-weight: bold; margin-bottom: 4px; color: #333; margin-top: 15px; }
        textarea, input[type="text"] { width: 100%; padding: 10px; box-sizing: border-box; border: 1px solid #ccc; border-radius: 4px; font-family: monospace; }
        textarea { height: 80px; resize: vertical; }
        button { margin-top: 15px; padding: 12px; width: 100%; background: #28a745; color: white; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
        button:hover { background: #218838; }
        .status { padding: 10px; background: #e8f5e9; border: 1px solid #c8e6c9; color: #2e7d32; border-radius: 4px; margin-bottom: 15px; }
        .info { margin-top: 20px; padding: 15px; background: #eef; border: 1px solid #ccd; border-radius: 4px; font-family: monospace; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>🛡️ Обновление клиента</h2>
        
        <script>
            if (window.location.search.includes('success=1')) {
                document.write('<div class="status">✅ Настройки сохранены! Служба перезапущена.</div>');
            }
        </script>

        <div class="info">
            <b>Сервер:</b> $CUR_PEER<br>
            <b>Профиль:</b> $CUR_OBF<br>
            <b>Ссылка VK:</b> <span style="word-break: break-all;">$CUR_VK_LINK</span>
        </div>

        <form method="POST" action="client.cgi">
            <label>1. Обновить данные сервера (Вставьте ссылку freeturn://)</label>
            <textarea id="linkInput" oninput="decodeLink()" placeholder="freeturn://..."></textarea>
            
            <div id="preview" style="display:none; margin-top: 10px; font-size: 14px; color: #0056b3;">
                <b>Новый сервер для сохранения:</b> <span id="newPeer"></span>
            </div>

            <input type="hidden" name="peer" id="inPeer">
            <input type="hidden" name="obf" id="inObf">
            <input type="hidden" name="key" id="inKey">

            <label>2. Ссылка на звонок VK (Можно обновлять отдельно)</label>
            <input type="text" name="vk_link" value="$CUR_VK_LINK" placeholder="https://vk.com/call/join/...">
            
            <button type="submit" id="applyBtn">Применить настройки и перезапустить</button>
        </form>

        <div id="wgBlock" style="display:none; margin-top: 25px; padding-top: 15px; border-top: 2px dashed #ccc;">
            <b style="color: #d32f2f;">Внимание!</b> Конфиг клиента WireGuard:
            <textarea id="outWg" readonly style="margin-top: 10px; height: 160px; background: #fafafa;"></textarea>
            <button type="button" onclick="copyText('outWg')" style="background: #007bff; margin-top: 10px;">📋 Скопировать конфиг WG</button>
        </div>
    </div>

    <script>
        function decodeLink() {
            let input = document.getElementById('linkInput').value.trim();
            let preview = document.getElementById('preview');
            let wgBlock = document.getElementById('wgBlock');
            
            if (!input.startsWith("freeturn://")) {
                preview.style.display = 'none'; wgBlock.style.display = 'none';
                document.getElementById('inPeer').value = '';
                document.getElementById('inObf').value = '';
                document.getElementById('inKey').value = '';
                return;
            }
            
            try {
                let base64Data = input.replace("freeturn://", "");
                while (base64Data.length % 4 !== 0) { base64Data += "="; }
                let config = JSON.parse(decodeURIComponent(escape(atob(base64Data))));
                
                document.getElementById('inPeer').value = config.peer;
                document.getElementById('inObf').value = config.obf;
                document.getElementById('inKey').value = config.key;
                
                document.getElementById('newPeer').innerText = config.peer;
                preview.style.display = 'block';

                if (config.wg && config.wg.trim() !== "") {
                    document.getElementById('outWg').value = config.wg;
                    wgBlock.style.display = 'block';
                } else {
                    wgBlock.style.display = 'none';
                }
            } catch (e) {
                preview.style.display = 'none'; wgBlock.style.display = 'none';
            }
        }

        function copyText(elementId) {
            let textArea = document.getElementById(elementId);
            textArea.select();
            try { document.execCommand('copy'); alert("✅ Конфиг WireGuard скопирован!"); } catch (err) { alert("❌ Ошибка копирования"); }
        }
    </script>
</body>
</html>
HTML_EOF
CLIENT_CGI_EOF

chmod +x /opt/share/www/client.cgi
sed -i 's/\r$//' /opt/share/www/client.cgi

echo "🔄 Запуск служб..."
killall lighttpd 2>/dev/null
sleep 1
/opt/etc/init.d/S80lighttpd start
/opt/etc/init.d/S98vk-turn-client restart > /dev/null 2>&1

LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
[ -z "$LAN_IP" ] && LAN_IP=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -n 1)

echo "====================================================="
echo "🎉 Клиент успешно установлен и запущен!"
echo "👉 Страница управления клиентом:"
echo "   http://${LAN_IP:-192.168.1.1}:8089/client.cgi"
echo "====================================================="

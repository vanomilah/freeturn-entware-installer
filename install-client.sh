#!/bin/sh

echo "====================================================="
echo "  🛡️ Автоматическая установка клиента FreeTurn + GUI"
echo "====================================================="

echo "📦 Установка зависимостей и локального веб-сервера..."
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
[ -z "$LATEST_VERSION" ] && LATEST_VERSION="v1.7.3"

FILE_NAME="client-linux-${FT_ARCH}"
DOWNLOAD_URL="https://mirror.ghproxy.com/https://github.com/samosvalishe/free-turn-proxy/releases/download/${LATEST_VERSION}/${FILE_NAME}"

echo "⬇️ Скачивание ${FILE_NAME} через зеркало..."
curl -4 -kL -o /opt/bin/freeturn-client "$DOWNLOAD_URL"

if [ -s "/opt/bin/freeturn-client" ]; then
    chmod +x /opt/bin/freeturn-client
else
    echo "❌ Ошибка скачивания клиентского бинарника!"
    exit 1
fi

# Инициализируем дефолтные переменные конфига
PEER=""
LINKS=""
OBF_PROFILE=""
OBF_KEY=""
THREADS="12"
STREAMS="6"
TRANSPORT="tcp"
MANUAL_CAPTCHA="yes"

echo "-----------------------------------------------------"
echo "📥 Хотите сразу импортировать настройки при установке?"
echo "   (Вставьте ссылку freeturn:// или нажмите Enter для пропуска)"
echo "-----------------------------------------------------"
printf "Ссылка: "
read -r FREETURN_LINK

if [ -n "$FREETURN_LINK" ] && echo "$FREETURN_LINK" | grep -q "^freeturn://"; then
    echo "🔑 Декодирование ссылки..."
    BASE64_DATA=$(echo "$FREETURN_LINK" | sed 's|^freeturn://||')
    # Добиваем base64 строку знаками "=" до кратности 4, если требуется
    MOD=$(( ${#BASE64_DATA} % 4 ))
    if [ $MOD -eq 2 ]; then BASE64_DATA="${BASE64_DATA}=="; fi
    if [ $MOD -eq 3 ]; then BASE64_DATA="${BASE64_DATA}="; fi
    
    JSON_DATA=$(echo "$BASE64_DATA" | tr '_-' '/+' | openssl enc -d -base64 -A 2>/dev/null)
    
    if [ -n "$JSON_DATA" ]; then
        # Парсим JSON простым sed/awk, чтобы не ставить тяжелый jq на роутер
        PEER=$(echo "$JSON_DATA" | grep -o '"peer":"[^"]*' | cut -d'"' -f4)
        LINKS=$(echo "$JSON_DATA" | grep -o '"links":"[^"]*' | cut -d'"' -f4)
        OBF_PROFILE=$(echo "$JSON_DATA" | grep -o '"obf":"[^"]*' | cut -d'"' -f4)
        OBF_KEY=$(echo "$JSON_DATA" | grep -o '"key":"[^"]*' | cut -d'"' -f4)
        echo "✅ Данные успешно импортированы!"
    else
        echo "⚠️  Ошибка декодирования base64. Настройки можно ввести позже в Web-интерфейсе."
    fi
fi

echo "⚙️ Запись файла конфигурации /opt/etc/vk-turn.conf..."
cat << CONF_EOF > /opt/etc/vk-turn.conf
PEER="$PEER"
LINKS="$LINKS"
OBF_PROFILE="$OBF_PROFILE"
OBF_KEY="$OBF_KEY"
CLIENT_ID="1aa1a31943b997ca7a8a4882b18f4bff"
LISTEN="127.0.0.1:9000"
THREADS="$THREADS"
STREAMS="$STREAMS"
TRANSPORT="$TRANSPORT"
MANUAL_CAPTCHA="$MANUAL_CAPTCHA"
CONF_EOF

echo "⚙️ Создание системной службы запуска..."
cat << 'INIT_EOF' > /opt/etc/init.d/S99vk-turn
#!/bin/sh
. /opt/etc/vk-turn.conf

PIDFILE=/opt/var/run/vk-turn.pid
LOGFILE=/opt/var/log/vk-turn.log

start() {
    if [ -z "$PEER" ]; then
        echo "Error: PEER is empty. Configure it via Web-UI." > $LOGFILE
        exit 1
    fi
    
    EXTRA_ARGS=""
    if [ "$MANUAL_CAPTCHA" = "yes" ]; then
        EXTRA_ARGS="-manual-captcha"
    fi
    
    /opt/bin/freeturn-client \
        -peer "$PEER" \
        -provider vk \
        -links "$LINKS" \
        -listen "$LISTEN" \
        -n "$THREADS" \
        -streams-per-cred "$STREAMS" \
        -transport "$TRANSPORT" \
        -obf-profile "$OBF_PROFILE" \
        -obf-key "$OBF_KEY" \
        -client-id "$CLIENT_ID" \
        $EXTRA_ARGS \
        -debug > $LOGFILE 2>&1 &
    echo $! > $PIDFILE
}

stop() {
    if [ -f "$PIDFILE" ]; then kill $(cat $PIDFILE) 2>/dev/null; fi
    killall freeturn-client 2>/dev/null
    rm -f $PIDFILE
}

case "$1" in
    start) start ;; 
    stop) stop ;; 
    restart) stop; sleep 2; start ;;
    status) if [ -f "$PIDFILE" ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then echo "RUNNING"; else echo "STOPPED"; fi ;;
esac
INIT_EOF

chmod 755 /opt/etc/init.d/S99vk-turn
sed -i 's/\r$//' /opt/etc/init.d/S99vk-turn

echo "🌐 Настройка веб-сервера lighttpd..."
CGI_CONF="/opt/etc/lighttpd/conf.d/30-cgi.conf"
if [ -f "$CGI_CONF" ]; then
    sed -i 's|".cgi" => "/opt/bin/perl"|".cgi" => "/bin/sh"|g' "$CGI_CONF"
    sed -i 's|#include "conf.d/30-cgi.conf"|include "conf.d/30-cgi.conf"|g' /opt/etc/lighttpd/lighttpd.conf
    sed -i '/server.port/d' /opt/etc/lighttpd/lighttpd.conf
    echo 'server.port = 8089' >> /opt/etc/lighttpd/lighttpd.conf
fi

mkdir -p /opt/share/www

echo "📝 Создание интерфейса управления client.cgi..."
cat << 'MAIN_CGI_EOF' > /opt/share/www/client.cgi
#!/bin/sh
export PATH="/opt/sbin:/opt/bin:/sbin:/bin:/usr/sbin:/usr/bin"
export LANG=C.UTF-8

CONFIG="/opt/etc/vk-turn.conf"
SERVICE="/opt/etc/init.d/S99vk-turn"
LOGFILE="/opt/var/log/vk-turn.log"

if [ "$QUERY_STRING" = "api_poll=1" ]; then
    echo "Content-type: application/json; charset=utf-8"
    echo -e "Cache-Control: no-cache\n"
    STATUS=$($SERVICE status)
    if [ -f "$LOGFILE" ]; then
        LOGS=$(tail -n 100 "$LOGFILE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | tr -d '\r')
    else
        LOGS="Логирование еще не началось."
    fi
    echo "{\"status\":\"$STATUS\", \"logs\":\"$LOGS\"}"
    exit 0
fi

if [ "$QUERY_STRING" = "action=start" ]; then $SERVICE start >/dev/null 2>&1; echo -e "Status: 303\nLocation: client.cgi\n"; exit 0; fi
if [ "$QUERY_STRING" = "action=stop" ]; then $SERVICE stop >/dev/null 2>&1; echo -e "Status: 303\nLocation: client.cgi\n"; exit 0; fi
if [ "$QUERY_STRING" = "action=restart" ]; then $SERVICE restart >/dev/null 2>&1; echo -e "Status: 303\nLocation: client.cgi\n"; exit 0; fi

if [ "$QUERY_STRING" = "action=abort_captcha" ]; then
    $SERVICE stop >/dev/null 2>&1
    > "$LOGFILE"
    sleep 1
    $SERVICE start >/dev/null 2>&1
    echo -e "Status: 303\nLocation: client.cgi\n"
    exit 0
fi

if [ "$REQUEST_METHOD" = "POST" ]; then
    POST_DATA=$(cat)
    
    DECODED=$(echo "$POST_DATA" | sed 's/+/ /g; s/%/\\x/g')
    DECODED=$(printf "$DECODED")

    NEW_PEER=$(echo "$DECODED" | grep -o 'peer=[^&]*' | cut -d= -f2 | tr -d "'\"")
    NEW_OBF=$(echo "$DECODED" | grep -o 'obf=[^&]*' | cut -d= -f2 | tr -d "'\"")
    NEW_KEY=$(echo "$DECODED" | grep -o 'key=[^&]*' | cut -d= -f2 | tr -d "'\"")
    NEW_VK=$(echo "$DECODED" | grep -o 'vk_links=[^&]*' | cut -d= -f2 | tr -d "'\"")
    NEW_THREADS=$(echo "$DECODED" | grep -o 'threads=[^&]*' | cut -d= -f2 | tr -d "'\"")
    NEW_STREAMS=$(echo "$DECODED" | grep -o 'streams=[^&]*' | cut -d= -f2 | tr -d "'\"")
    NEW_TRANSPORT=$(echo "$DECODED" | grep -o 'transport=[^&]*' | cut -d= -f2 | tr -d "'\"")

    if echo "$POST_DATA" | grep -q "manual_captcha=on"; then CAPTCHA_TOGGLE="yes"; else CAPTCHA_TOGGLE="no"; fi

    cat << CONF_EOF > "$CONFIG"
PEER="$NEW_PEER"
LINKS="$NEW_VK"
OBF_PROFILE="$NEW_OBF"
OBF_KEY="$NEW_KEY"
CLIENT_ID="1aa1a31943b997ca7a8a4882b18f4bff"
LISTEN="127.0.0.1:9000"
THREADS="${NEW_THREADS:-12}"
STREAMS="${NEW_STREAMS:-6}"
TRANSPORT="${NEW_TRANSPORT:-tcp}"
MANUAL_CAPTCHA="$CAPTCHA_TOGGLE"
CONF_EOF

    $SERVICE restart > /dev/null 2>&1
    echo -e "Status: 303 See Other\nLocation: client.cgi?saved=1\n"
    exit 0
fi

PEER=""
LINKS=""
OBF_PROFILE=""
OBF_KEY=""
THREADS="12"
STREAMS="6"
TRANSPORT="tcp"
MANUAL_CAPTCHA="yes"

if [ -f "$CONFIG" ]; then . "$CONFIG"; fi

echo "Content-type: text/html; charset=utf-8"
echo -e "Cache-Control: no-cache\n"

cat << HTML_INNER_EOF
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Панель FreeTurn</title>
<style>
body{font-family:sans-serif;padding:20px;max-width:800px;margin:auto;background:#f4f6f9;color:#333}
.card{background:#fff;padding:24px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.05);margin-bottom:20px}
h2{margin-top:0;border-bottom:2px solid #edf2f7;padding-bottom:12px;font-size:20px}
label{display:block;font-size:13px;font-weight:600;margin-bottom:6px;margin-top:16px;color:#4a5568}
input[type="text"],input[type="number"],select,textarea{width:100%;padding:10px;box-sizing:border-box;border:1px solid #cbd5e0;border-radius:6px;font-family:monospace;font-size:14px;background:#fff}
.btn{padding:10px 20px;border:none;border-radius:6px;font-size:14px;font-weight:bold;cursor:pointer;text-decoration:none;display:inline-block;text-align:center}
.btn-primary{background:#3182ce;color:#fff;width:100%;margin-top:20px;padding:12px;font-size:16px}
.btn-action{color:#fff;min-width:100px;margin-right:8px}
.status-bar{display:flex;align-items:center;justify-content:space-between;background:#edf2f7;padding:12px 20px;border-radius:8px;font-weight:bold;margin-bottom:20px}
.status-running{color:#38a169} .status-stopped{color:#e53e3e}
.log-box{background:#1a202c;color:#48bb78;font-family:monospace;font-size:12px;padding:14px;border-radius:6px;height:350px;overflow-y:auto;white-space:pre-wrap;margin-top:8px}
.flex-group{display:flex;gap:16px} .flex-child{flex:1}
.checkbox-container{display:flex;flex-direction:column;gap:6px;margin-top:16px;background:#f7fafc;padding:12px;border-radius:6px;border:1px solid #e2e8f0}
.checkbox-label{display:flex;align-items:center;font-size:14px;cursor:pointer;margin:0;font-weight:600}
.alert-success{background:#c6f6d5;color:#22543d;padding:12px;border-radius:6px;margin-bottom:15px;font-weight:500}
#captchaModal{display:none;position:fixed;z-index:1000;left:0;top:0;width:100%;height:100%;background:rgba(0,0,0,0.6);backdrop-filter:blur(4px)}
.modal-content{background:#fff;margin:6% auto;padding:24px;border-radius:12px;width:95%;max-width:550px;box-shadow:0 10px 25px rgba(0,0,0,0.3);text-align:center;position:relative}
.modal-header{background:#dd6b20;color:#fff;padding:14px;font-size:18px;font-weight:bold;margin:-24px -24px 20px -24px;border-radius:12px 12px 0 0;position:relative}
.close-x{position:absolute;right:15px;top:12px;color:#fff;font-size:24px;text-decoration:none;font-weight:normal;cursor:pointer;line-height:20px;opacity:0.8}
.close-x:hover{opacity:1}
.btn-captcha{background:#dd6b20;color:white;padding:12px 24px;font-size:15px;font-weight:bold;display:inline-block;border-radius:6px;text-decoration:none;margin-top:15px;box-shadow:0 4px 10px rgba(221,107,32,0.3);width:48%;box-sizing:border-box;margin-right:2%}
.btn-abort{background:#e53e3e;color:white;padding:12px 24px;font-size:15px;font-weight:bold;display:inline-block;border-radius:6px;text-decoration:none;margin-top:15px;width:48%;box-sizing:border-box}
.modal-log-box{background:#1a202c;color:#a3e635;font-family:monospace;font-size:11px;padding:10px;border-radius:6px;height:180px;overflow-y:auto;white-space:pre-wrap;margin-top:15px;text-align:left;border:1px solid #4a5568}
.hint-text{font-size:11px;color:#718096;margin-left:22px;line-height:1.4;font-weight:normal}
</style></head><body>

<div id="captchaModal">
    <div class="modal-content">
        <div class="modal-header">🧩 Требуется решение VK Капчи<span class="close-x" onclick="closeModalSoft()">&times;</span></div>
        <p style="font-size:14px;color:#4a5568;line-height:1.5;margin:0">Скопируйте команду ниже в terminal вашего ПК для проброса порта, а затем откройте страницу капчи:</p>
        <input type="text" id="sshCmd" readonly style="margin:12px 0;background:#f7fafc;text-align:center;" onclick="this.select()">
        <div>
            <a href="http://localhost:8765" target="_blank" class="btn btn-captcha">Открыть капчу ↗</a>
            <a href="client.cgi?action=abort_captcha" class="btn btn-abort">Сбросить службу</a>
        </div>
        <div class="modal-log-box" id="modalLogConsole">Загрузка логов...</div>
    </div>
</div>

<div class="card"><h2>📊 Состояние службы</h2><div class="status-bar"><div>Текущий статус: <span id="statusIndicator">Загрузка...</span></div><div><a href="client.cgi?action=start" class="btn btn-action" style="background:#38a169">Старт</a> <a href="client.cgi?action=stop" class="btn btn-action" style="background:#e53e3e">Стоп</a> <a href="client.cgi?action=restart" class="btn btn-action" style="background:#dd6b20">Рестарт</a></div></div></div>
<div class="card"><h2>⚙️ Полная конфигурация</h2><script>if(window.location.search.includes('saved=1')) document.write('<div class="alert-success">✅ Настройки сохранены!</div>');</script>
<form method="POST"><label style="color:#2b6cb0">📥 Расшифровка (freeturn://)</label><textarea id="decoderInput" style="height:45px" oninput="parseFreeTurnLink()"></textarea>
<div class="flex-group"><div class="flex-child"><label>Адрес (-peer)</label><input type="text" name="peer" value="$PEER" required></div><div class="flex-child"><label>Профиль</label><input type="text" name="obf" value="$OBF_PROFILE" required></div></div>
<label>Ключ (-obf-key)</label><input type="text" name="key" value="$OBF_KEY" required>
<label>Ссылки VK (-links)</label><textarea name="vk_links" style="height:70px" required>$LINKS</textarea>

<h3 style="margin:24px 0 10px 0;border-bottom:1px solid #edf2f7;padding-bottom:8px;font-size:16px;color:#4a5568">🛠️ Дополнительные настройки</h3>
<div class="flex-group">
    <div class="flex-child"><label>Потоки (-n)</label><input type="number" name="threads" value="$THREADS" min="1" max="100" required></div>
    <div class="flex-child"><label>Стримы (на кред)</label><input type="number" name="streams" value="$STREAMS" min="1" max="50" required></div>
    <div class="flex-child">
        <label>Протокол</label>
        <select name="transport">
            <option value="tcp" $([ "$TRANSPORT" = "tcp" ] && echo "selected")>TCP</option>
            <option value="udp" $([ "$TRANSPORT" = "udp" ] && echo "selected")>UDP</option>
        </select>
    </div>
</div>

<div class="checkbox-container">
    <label class="checkbox-label" style="color:#c53030">
        <input type="checkbox" name="manual_captcha" id="captchaCheckbox" $([ "$MANUAL_CAPTCHA" = "yes" ] && echo "checked")>🧩 Обработка сложной капчи
    </label>
    <div class="hint-text">💡 При включении этой функции, при появлении капчи вам потребуется пробросить порт 8765 через SSH-туннель на вашем ПК для ручного ввода символов. Команда для проброса сгенерируется автоматически.</div>
</div>
<button type="submit" class="btn btn-primary">Применить и перезапустить</button></form></div>
<div class="card"><h2>📜 Терминал логов</h2><div class="log-box" id="logConsole">Загрузка...</div></div>
<script>
let forceClosed = false;
function parseFreeTurnLink() { 
    let i=document.getElementById('decoderInput').value.trim(); 
    if(!i.startsWith("freeturn://")) return; 
    try{ 
        let b=i.replace("freeturn://",""); 
        while(b.length%4!==0)b+="="; 
        let p=JSON.parse(decodeURIComponent(escape(atob(b)))); 
        if(p.peer) document.getElementsByName('peer')[0].value=p.peer; 
        if(p.obf) document.getElementsByName('obf')[0].value=p.obf; 
        if(p.key) document.getElementsByName('key')[0].value=p.key; 
        if(p.links) document.getElementsByName('vk_links')[0].value=p.links; 
    }catch(e){} 
}

document.getElementById('sshCmd').value = "ssh -N -L 8765:127.0.0.1:8765 root@" + window.location.hostname + " -p 222";

function closeModalSoft() { forceClosed = true; document.getElementById('captchaModal').style.display = "none"; }

function pollSystem() { 
    fetch('client.cgi?api_poll=1').then(r=>r.json()).then(data=>{ 
        let i=document.getElementById('statusIndicator'); i.innerText=data.status; i.className=data.status==="RUNNING"?"status-running":"status-stopped"; 
        
        let c=document.getElementById('logConsole'); let scr=c.scrollTop+c.clientHeight>=c.scrollHeight-40; c.innerText=data.logs; if(scr) c.scrollTop=c.scrollHeight;
        let mc=document.getElementById('modalLogConsole'); let mScr=mc.scrollTop+mc.clientHeight>=mc.scrollHeight-40; mc.innerText=data.logs; if(mScr) mc.scrollTop=mc.scrollHeight;
        
        let m=document.getElementById('captchaModal');
        if(!forceClosed && document.getElementById('captchaCheckbox').checked && data.logs.includes("MANUAL CAPTCHA SOLVING NEEDED")){
            if(m.style.display !== "block") m.style.display = "block";
        } else if (!data.logs.includes("MANUAL CAPTCHA SOLVING NEEDED")) { 
            forceClosed = false;
            if(m.style.display === "block") m.style.display = "none"; 
        }
    }); 
}
document.addEventListener("DOMContentLoaded",()=>{ setInterval(pollSystem,1000); pollSystem(); });
</script></body></html>
HTML_INNER_EOF
MAIN_CGI_EOF

chmod 755 /opt/share/www/client.cgi
sed -i 's/\r$//' /opt/share/www/client.cgi

/opt/etc/init.d/S80lighttpd restart

LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
[ -z "$LAN_IP" ] && LAN_IP=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -n 1)

# Запускаем службу только в том случае, если пир был успешно настроен во время установки
if [ -n "$PEER" ]; then
    echo "🚀 Запуск службы..."
    /opt/etc/init.d/S99vk-turn start >/dev/null 2>&1
fi

echo "====================================================="
echo "🎉 Проект FreeTurn Web-GUI успешно установлен!"
echo "👉 Админка доступна по ссылке: http://${LAN_IP:-192.168.1.1}:8089/client.cgi"
echo "====================================================="
INSTALL_EOF

sh /tmp/install-client.sh

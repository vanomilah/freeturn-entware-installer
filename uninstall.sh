#!/bin/sh

echo "====================================================="
echo "  🗑️ Удаление FreeTurn (Сервер/Клиент)"
echo "====================================================="

# 1. Список файлов и служб
SERVICES="S99vk-turn-server S98vk-turn-client"
BINARIES="/opt/bin/freeturn-server /opt/bin/freeturn-client"
WWW_DIR="/opt/share/www"

# 2. Остановка и удаление служб
for svc in $SERVICES; do
    if [ -f "/opt/etc/init.d/$svc" ]; then
        echo "🛑 Остановка службы $svc..."
        /opt/etc/init.d/$svc stop > /dev/null 2>&1
        rm -f "/opt/etc/init.d/$svc"
        echo "✅ Служба $svc удалена."
    fi
done

# 3. Удаление бинарников
for bin in $BINARIES; do
    if [ -f "$bin" ]; then
        rm -f "$bin"
        echo "✅ Бинарник $bin удален."
    fi
done

# 4. Удаление веб-интерфейса
if [ -d "$WWW_DIR" ]; then
    echo "🌐 Удаление веб-интерфейса..."
    rm -rf "$WWW_DIR/generator.cgi"
    rm -rf "$WWW_DIR/client.cgi"
    rm -rf "$WWW_DIR/decoder.html"
fi

# 5. Перезапуск веб-сервера
echo "🔄 Перезапуск веб-сервера..."
killall lighttpd 2>/dev/null
/opt/etc/init.d/S80lighttpd restart > /dev/null 2>&1

echo "====================================================="
echo "🎉 FreeTurn успешно удален с роутера!"
echo "====================================================="

#!/bin/sh

echo "====================================================="
echo "  🧹 Полное удаление FreeTurn + Web Generator"
echo "====================================================="

echo "⏹️  Останавливаем службы..."
# Останавливаем FreeTurn, если скрипт существует
if [ -f "/opt/etc/init.d/S99vk-turn-server" ]; then
    /opt/etc/init.d/S99vk-turn-server stop >/dev/null 2>&1
fi

# Останавливаем lighttpd
/opt/etc/init.d/S80lighttpd stop >/dev/null 2>&1

# Добиваем зависшие процессы на всякий случай
killall freeturn-server 2>/dev/null
killall lighttpd 2>/dev/null

echo "🗑️  Удаляем сервер FreeTurn..."
rm -f /opt/bin/freeturn-server
rm -f /opt/etc/init.d/S99vk-turn-server
rm -f /opt/var/run/freeturn-server.pid

echo "🗑️  Удаляем веб-генератор..."
rm -f /opt/share/www/generator.cgi

echo "⏪ Возвращаем стандартные настройки lighttpd..."
CGI_CONF="/opt/etc/lighttpd/conf.d/30-cgi.conf"
if [ -f "$CGI_CONF" ]; then
    # Меняем /bin/sh обратно на стандартный /opt/bin/perl
    sed -i 's|".cgi" => "/bin/sh"|".cgi" => "/opt/bin/perl"|g' "$CGI_CONF"
fi

echo "🚀 Запускаем веб-сервер обратно..."
/opt/etc/init.d/S80lighttpd start >/dev/null 2>&1

echo "====================================================="
echo "✅ Все созданные файлы и скрипты успешно удалены!"
echo "====================================================="
echo "💡 Примечание: Сами пакеты (lighttpd, wget) оставлены в системе."
echo "   Если веб-сервер вам больше вообще не нужен,"
echo "   вы можете удалить его пакеты командой:"
echo "   opkg remove lighttpd lighttpd-mod-cgi"
echo "====================================================="

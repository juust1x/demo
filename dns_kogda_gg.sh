
#!/bin/bash
set -e

echo "=== Настройка DNS-сервера на HQ-SRV ==="

# Установка пакетов
apt-get update && apt-get install -y bind nano

# Очистка/создание рабочей директории (на всякий случай)
mkdir -p /etc/bind

# --- Конфигурация BIND ---
# options.conf — здесь только опции, без лишних конструкций
cat > /etc/bind/options.conf <<'EOF'
listen-on { any; };
listen-on-v6 { none; };
forward first;
forwarders { 9.9.9.9; };
allow-query { any; };
recursion yes;
EOF

# Убедимся, что основной named.conf корректно включает options.conf
# Проверяем, есть ли include в named.conf
if ! grep -q 'include.*options.conf' /etc/bind/named.conf 2>/dev/null; then
    # Создаём чистый named.conf с правильными include
    cat > /etc/bind/named.conf <<'EOF'
include "/etc/bind/options.conf";
include "/etc/bind/local.conf";
EOF
fi

# local.conf с зонами
cat > /etc/bind/local.conf <<'EOF'
// Зона прямого просмотра (A-записи)
zone "au-team.irpo" {
    type master;
    file "/etc/bind/db.au-team.irpo";
};

// Зона обратного просмотра для сети 192.168.100.0/27
zone "100.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.100";
};

// Зона обратного просмотра для сети 192.168.200.64/28
zone "64.200.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.200.64";
};
EOF

# Файл прямой зоны au-team.irpo
cat > /etc/bind/db.au-team.irpo <<'EOF'
$TTL 86400
@   IN  SOA hq-srv.au-team.irpo. root.au-team.irpo. (
        2025121001 ; serial
        3600       ; refresh
        1800       ; retry
        604800     ; expire
        86400 )    ; minimum

    IN  NS  hq-srv.au-team.irpo.

hq-rtr   IN  A   192.168.100.1
br-rtr   IN  A   192.168.3.1
hq-srv   IN  A   192.168.100.2
hq-cli   IN  A   192.168.200.66
br-srv   IN  A   192.168.3.2

docker  IN  A   172.16.1.1
web     IN  A   172.16.2.1
EOF

# Файл обратной зоны 192.168.100
cat > /etc/bind/db.192.168.100 <<'EOF'
$TTL 86400
@   IN  SOA hq-srv.au-team.irpo. root.au-team.irpo. (
        2025121001
        3600
        1800
        604800
        86400 )

    IN  NS  hq-srv.au-team.irpo.

1   IN  PTR  hq-rtr.au-team.irpo.
2   IN  PTR  hq-srv.au-team.irpo.
EOF

# Файл обратной зоны 192.168.200.64
cat > /etc/bind/db.192.168.200.64 <<'EOF'
$TTL 86400
@   IN  SOA hq-srv.au-team.irpo. root.au-team.irpo. (
        2025121001
        3600
        1800
        604800
        86400 )

    IN  NS  hq-srv.au-team.irpo.

1  IN  PTR  hq-cli.au-team.irpo.
EOF

# Проверка синтаксиса перед запуском
echo "Проверка конфигурации BIND..."
named-checkconf /etc/bind/named.conf
if [ $? -eq 0 ]; then
    echo "Синтаксис конфигурации OK"
else
    echo "ОШИБКА в конфигурации!"
    exit 1
fi

# Проверка зон
named-checkzone au-team.irpo /etc/bind/db.au-team.irpo
named-checkzone 100.168.192.in-addr.arpa /etc/bind/db.192.168.100
named-checkzone 64.200.168.192.in-addr.arpa /etc/bind/db.192.168.200.64

# --- Настройка локального резолвера ---
# Удаляем старый resolv.conf интерфейса (если есть)
rm -f /etc/net/ifaces/enp7s1/resolv.conf
systemctl restart network

# Указываем использовать локальный DNS
cat > /etc/resolvconf.conf <<'EOF'
name_servers=127.0.0.1
EOF

resolvconf -u
systemctl restart network

# --- Запуск и активация BIND ---
systemctl enable --now bind
systemctl restart bind
systemctl status bind --no-pager

echo "DNS-сервер на HQ-SRV настроен успешно."

#!/bin/bash
set -e

echo "=== Настройка GRE-туннеля и DHCP на HQ-RTR ==="

# --- IP-туннель GRE ---
mkdir -p /etc/net/ifaces/gre1

cat > /etc/net/ifaces/gre1/options <<EOF
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.1.2
TUNREMOTE=172.16.2.2
TUNOPTIONS='ttl 64'
EOF

echo "10.10.0.1/30" > /etc/net/ifaces/gre1/ipv4address

systemctl restart network

# Проверяем, что VLAN-интерфейс для DHCP существует и активен
echo "Ожидание поднятия интерфейса enp7s2.200..."
sleep 3
if ! ip link show enp7s2.200 &>/dev/null; then
    echo "ОШИБКА: интерфейс enp7s2.200 не найден!"
    echo "Доступные интерфейсы:"
    ip -br link show
    exit 1
fi

# --- DHCP-сервер ---
apt-get update && apt-get install -y dhcp-server nano

# Остановим DHCP перед настройкой
systemctl stop dhcpd 2>/dev/null || true

# Конфигурация DHCP (полная замена)
cat > /etc/dhcp/dhcpd.conf <<'EOF'
# Глобальные настройки
authoritative;
ddns-update-style none;

# Подсеть для VLAN 200 (HQ-CLI)
subnet 192.168.200.64 netmask 255.255.255.240 {
        option routers                  192.168.200.65;
        option subnet-mask              255.255.255.240;
        option domain-name              "au-team.irpo";
        option domain-name-servers      192.168.100.2;
        range dynamic-bootp 192.168.200.66 192.168.200.78;
        default-lease-time 600;
        max-lease-time 7200;
}

# Подсеть для VLAN 100 (чтобы DHCP не жаловался на отсутствие)
subnet 192.168.100.0 netmask 255.255.255.224 {
        # Нет динамических адресов, только статика
}

# Подсеть для VLAN 999 (чтобы DHCP не жаловался на отсутствие)
subnet 192.168.99.88 netmask 255.255.255.248 {
        # Нет динамических адресов
}
EOF

# Настройка привязки к интерфейсу
# В Alt Linux настройка через /etc/sysconfig/dhcpd
cat > /etc/sysconfig/dhcpd <<EOF
DHCPDARGS="enp7s2.200"
EOF

# Альтернативный способ - правка systemd-юнита
# Создаём override для сервиса dhcpd
mkdir -p /etc/systemd/system/dhcpd.service.d
cat > /etc/systemd/system/dhcpd.service.d/interface.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/dhcpd -f -cf /etc/dhcp/dhcpd.conf -user dhcpd -group dhcpd enp7s2.200
EOF

# Перечитываем конфигурацию systemd
systemctl daemon-reload

# Проверка конфигурации перед запуском
echo "Проверка конфигурации DHCP..."
/usr/sbin/dhcpd -t -cf /etc/dhcp/dhcpd.conf
if [ $? -ne 0 ]; then
    echo "ОШИБКА в конфигурации DHCP!"
    exit 1
fi

# Запуск и включение
systemctl enable dhcpd
systemctl restart dhcpd
sleep 2
systemctl status dhcpd --no-pager

# Проверка логирования для отладки
echo "=== Логи DHCP ==="
journalctl -u dhcpd -n 20 --no-pager

echo "GRE-туннель и DHCP на HQ-RTR настроены."

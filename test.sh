#!/bin/bash
# dhcp_dns.sh – настройка головного сервера ALT Linux (DNS + DHCP + NAT)
# Все параметры заданы жёстко, интерактивный ввод удалён.
# Подсети:
#   WAN (eth0): 10.10.10.0/24
#   LAN1(eth1): 20.20.20.0/24
#   LAN2(eth2): 30.30.30.0/24
# Хост: isp.kyki.umer
# Домен: kyki.umer

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен выполняться с правами root (sudo)."
   exit 1
fi

# -------------------------------------------------------------
# 1. Параметры (заданы статически)
# -------------------------------------------------------------
WAN_IFACE="eth0"
LAN1_IFACE="eth1"
LAN2_IFACE="eth2"

WAN_IP="10.10.10.1/24"
LAN1_IP="20.20.20.1/24"
LAN2_IP="30.30.30.1/24"

DOMAIN="kyki.umer"
HOSTNAME="isp.${DOMAIN}"          # Полное доменное имя сервера

# Производные
WAN_ADDR="10.10.10.1"
LAN1_ADDR="20.20.20.1"
LAN2_ADDR="30.30.30.1"
LAN1_NETWORK="20.20.20.0"
LAN2_NETWORK="30.30.30.0"
PREFIX="24"

echo "Будут настроены:"
echo "  $WAN_IFACE : $WAN_IP (внешний)"
echo "  $LAN1_IFACE: $LAN1_IP (внутренняя сеть $LAN1_NETWORK/$PREFIX)"
echo "  $LAN2_IFACE: $LAN2_IP (внутренняя сеть $LAN2_NETWORK/$PREFIX)"
echo "  Хост      : $HOSTNAME"
echo "  Домен     : $DOMAIN"
echo

# -------------------------------------------------------------
# 2. Обновление репозиториев и установка пакетов
# -------------------------------------------------------------
echo "Обновление репозиториев..."
apt-get update -y

echo "Установка пакетов (dhcp-server, bind, iptables)..."
apt-get install -y dhcp-server bind iptables

# -------------------------------------------------------------
# 3. Установка имени хоста
# -------------------------------------------------------------
echo "Установка имени хоста: $HOSTNAME"
hostnamectl set-hostname "$HOSTNAME"

# -------------------------------------------------------------
# 4. Настройка статических IP (ALT Linux)
# -------------------------------------------------------------
configure_iface() {
    local iface="$1"
    local addr="$2"

    mkdir -p "/etc/net/ifaces/$iface"

    cat > "/etc/net/ifaces/$iface/options" <<EOF
TYPE=eth
DISABLED=no
BOOTPROTO=static
EOF

    echo "${addr}/${PREFIX}" > "/etc/net/ifaces/$iface/ipv4address"
}

# Останавливаем NetworkManager, чтобы не конфликтовал
systemctl stop NetworkManager 2>/dev/null || true
systemctl disable NetworkManager 2>/dev/null || true

echo "Настройка интерфейса $WAN_IFACE..."
configure_iface "$WAN_IFACE" "$WAN_ADDR"

echo "Настройка интерфейса $LAN1_IFACE..."
configure_iface "$LAN1_IFACE" "$LAN1_ADDR"

echo "Настройка интерфейса $LAN2_IFACE..."
configure_iface "$LAN2_IFACE" "$LAN2_ADDR"

echo "Перезапуск сети..."
systemctl restart network
sleep 2

# -------------------------------------------------------------
# 5. Включение IP-маршрутизации
# -------------------------------------------------------------
echo "Включение IP forwarding..."
sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# -------------------------------------------------------------
# 6. Настройка iptables (NAT + базовый firewall)
# -------------------------------------------------------------
echo "Настройка iptables..."

iptables -F
iptables -t nat -F
iptables -X

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH на внешнем интерфейсе
iptables -A INPUT -i "$WAN_IFACE" -p tcp --dport 22 -j ACCEPT

# DNS и DHCP на внутренних интерфейсах
for iface in "$LAN1_IFACE" "$LAN2_IFACE"; do
    iptables -A INPUT -i "$iface" -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i "$iface" -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -i "$iface" -p udp --dport 67 -j ACCEPT
done

# Форвардинг из локальных сетей наружу
iptables -A FORWARD -i "$LAN1_IFACE" -o "$WAN_IFACE" -j ACCEPT
iptables -A FORWARD -i "$LAN2_IFACE" -o "$WAN_IFACE" -j ACCEPT

# NAT (маскарадинг)
iptables -t nat -A POSTROUTING -o "$WAN_IFACE" -j MASQUERADE

# Сохранение правил
iptables-save > /etc/sysconfig/iptables
if systemctl list-unit-files | grep -q iptables.service; then
    systemctl enable iptables
    systemctl restart iptables
else
    grep -q 'iptables-restore' /etc/rc.local || echo 'iptables-restore < /etc/sysconfig/iptables' >> /etc/rc.local
    chmod +x /etc/rc.local
fi

echo "iptables настроен."

# -------------------------------------------------------------
# 7. Настройка DNS-сервера (bind)
# -------------------------------------------------------------
echo "Настройка DNS (bind)..."

cp -n /etc/bind/options.conf /etc/bind/options.conf.bak 2>/dev/null || true

cat > /etc/bind/options.conf <<EOF
options {
    directory "/var/cache/bind";
    listen-on { any; };
    allow-query { any; };
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    dnssec-validation auto;
};
EOF

mkdir -p /var/cache/bind/zones

# Прямая зона kyki.umer
cat > "/var/cache/bind/zones/db.${DOMAIN}" <<EOF
\$TTL 86400
@   IN  SOA ${HOSTNAME}. admin.${DOMAIN}. (
        $(date +%Y%m%d)01 ; serial
        3600        ; refresh
        1800        ; retry
        604800      ; expire
        86400 )     ; minimum

@       IN  NS  ${HOSTNAME}.
${HOSTNAME%.${DOMAIN}} IN A ${LAN1_ADDR}   ; isp.kyki.umer доступен в LAN1
EOF

# Обратная зона для 20.20.20.0/24
cat > "/var/cache/bind/zones/db.20.20.20" <<EOF
\$TTL 86400
@   IN  SOA ${HOSTNAME}. admin.${DOMAIN}. (
        $(date +%Y%m%d)02 ; serial
        3600
        1800
        604800
        86400 )

@       IN  NS  ${HOSTNAME}.
1       IN  PTR ${HOSTNAME}.
EOF

# Обратная зона для 30.30.30.0/24
cat > "/var/cache/bind/zones/db.30.30.30" <<EOF
\$TTL 86400
@   IN  SOA ${HOSTNAME}. admin.${DOMAIN}. (
        $(date +%Y%m%d)03 ; serial
        3600
        1800
        604800
        86400 )

@       IN  NS  ${HOSTNAME}.
1       IN  PTR ${HOSTNAME}.
EOF

# Подключаем зоны
cat > /etc/bind/local.conf <<EOF
zone "${DOMAIN}" {
    type master;
    file "/var/cache/bind/zones/db.${DOMAIN}";
};

zone "20.20.20.in-addr.arpa" {
    type master;
    file "/var/cache/bind/zones/db.20.20.20";
};

zone "30.30.30.in-addr.arpa" {
    type master;
    file "/var/cache/bind/zones/db.30.30.30";
};
EOF

if ! grep -q 'include "/etc/bind/local.conf"' /etc/bind/named.conf; then
    echo 'include "/etc/bind/local.conf";' >> /etc/bind/named.conf
fi

systemctl enable --now bind

# -------------------------------------------------------------
# 8. Настройка DHCP-сервера
# -------------------------------------------------------------
echo "Настройка DHCP-сервера..."

cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time 86400;
max-lease-time 172800;
ddns-update-style none;
authoritative;

option domain-name "${DOMAIN}";
option domain-name-servers ${LAN1_ADDR}, ${LAN2_ADDR};

# Подсеть 20.20.20.0/24
subnet ${LAN1_NETWORK} netmask 255.255.255.0 {
    range 20.20.20.100 20.20.20.200;
    option routers ${LAN1_ADDR};
    option broadcast-address 20.20.20.255;
}

# Подсеть 30.30.30.0/24
subnet ${LAN2_NETWORK} netmask 255.255.255.0 {
    range 30.30.30.100 30.30.30.200;
    option routers ${LAN2_ADDR};
    option broadcast-address 30.30.30.255;
}
EOF

cat > /etc/sysconfig/dhcpd <<EOF
DHCPDARGS="${LAN1_IFACE} ${LAN2_IFACE}"
EOF

systemctl enable --now dhcpd

# -------------------------------------------------------------
# 9. Финальная проверка
# -------------------------------------------------------------
echo
echo "========================================="
echo " Настройка завершена."
echo "========================================="
ip -4 addr show "$WAN_IFACE" "$LAN1_IFACE" "$LAN2_IFACE" | grep inet
echo
echo "Службы:"
systemctl is-active bind && echo "  DNS (bind)   : active" || echo "  DNS (bind)   : FAILED"
systemctl is-active dhcpd && echo "  DHCP (dhcpd) : active" || echo "  DHCP (dhcpd) : FAILED"
echo
echo "Проверьте правила iptables: iptables -L -n -v"
echo "Сервер готов к работе."

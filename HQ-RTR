#!/bin/bash
set -e

echo "=== Настройка HQ-RTR ==="

# hostname
hostnamectl set-hostname hq-rtr.au-team.irpo

# Создание каталогов
mkdir -p /etc/net/ifaces/enp7s1
mkdir -p /etc/net/ifaces/enp7s2
mkdir -p /etc/net/ifaces/enp7s2.100
mkdir -p /etc/net/ifaces/enp7s2.200
mkdir -p /etc/net/ifaces/enp7s2.999

# enp7s1 (внешний интерфейс)
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "172.16.1.2/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 172.16.1.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 9.9.9.9" > /etc/net/ifaces/enp7s1/resolv.conf

# enp7s2 (trunk, без IP)
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=none
TYPE=eth
EOF

# VLAN 100 – сеть HQ-SRV
cat > /etc/net/ifaces/enp7s2.100/options <<EOF
BOOTPROTO=static
TYPE=vlan
VID=100
HOST=enp7s2
EOF
echo "192.168.100.1/27" > /etc/net/ifaces/enp7s2.100/ipv4address

# VLAN 200 – сеть HQ-CLI (предположительно)
cat > /etc/net/ifaces/enp7s2.200/options <<EOF
BOOTPROTO=static
TYPE=vlan
VID=200
HOST=enp7s2
EOF
echo "192.168.200.65/28" > /etc/net/ifaces/enp7s2.200/ipv4address

# VLAN 999 – управление
cat > /etc/net/ifaces/enp7s2.999/options <<EOF
BOOTPROTO=static
TYPE=vlan
VID=999
HOST=enp7s2
EOF
echo "192.168.99.89/29" > /etc/net/ifaces/enp7s2.999/ipv4address

# Перезапуск сети
systemctl restart network

echo "Настройка HQ-RTR завершена."

echo "=== Настройка HQ-RTR: интернет, время ==="

# --- IP Forwarding ---
sed -i '/^net.ipv4.ip_forward/d' /etc/net/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf
sysctl -p
systemctl restart network

# --- Установка и настройка iptables ---
apt-get update && apt-get install -y iptables

iptables -t nat -A POSTROUTING -o enp7s1 -s 192.168.100.0/27 -j MASQUERADE
iptables -t nat -A POSTROUTING -o enp7s1 -s 192.168.200.64/28 -j MASQUERADE
iptables -t nat -A POSTROUTING -o enp7s1 -s 192.168.99.88/29 -j MASQUERADE
iptables -A FORWARD -i ens19.10 -o enp7s1 -s 192.168.100.0/27 -j ACCEPT
iptables -A FORWARD -i ens19.20 -o enp7s1 -s 192.168.200.64/28 -j ACCEPT
iptables -A FORWARD -i ens19.99 -o enp7s1 -s 192.168.99.88/29 -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables --now
systemctl restart iptables
systemctl status iptables --no-pager
iptables -t nat -L -n -v

# --- Часовой пояс (tzdata) ---
apt-get install -y tzdata
timedatectl set-timezone Europe/Moscow
timedatectl

echo "HQ-RTR: настройка завершена."


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

# --- DHCP-сервер ---
apt-get update && apt-get install -y dhcp-server nano

# Запись конфигурационного файла DHCP (полная замена)
cat > /etc/dhcp/dhcpd.conf <<EOF
subnet 192.168.200.64 netmask 255.255.255.240 {
        option routers                  192.168.200.65;
        option subnet-mask              255.255.255.240;

        option domain-name              "au-team.irpo";
        option domain-name-servers      192.168.100.2;

        range dynamic-bootp 192.168.200.66 192.168.200.78;
        default-lease-time 600;
        max-lease-time 7200;
}
EOF

systemctl enable --now dhcpd
systemctl restart dhcpd

echo "GRE-туннель и DHCP на HQ-RTR настроены."


echo "=== Настройка DNS-клиента на HQ-RTR ==="

# Замена DNS-сервера на интерфейсе enp7s1
echo "nameserver 192.168.100.2" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network
systemctl restart dhcpd

echo "DNS-клиент на HQ-RTR обновлён."

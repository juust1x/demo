#!/bin/bash
set -e

echo "=== Настройка BR-RTR ==="

# hostname
hostnamectl set-hostname br-rtr.au-team.irpo

# Каталоги интерфейсов
mkdir -p /etc/net/ifaces/enp7s1
mkdir -p /etc/net/ifaces/enp7s2

# enp7s1 (внешний, к ISP)
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "172.16.2.2/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 172.16.2.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 9.9.9.9" > /etc/net/ifaces/enp7s1/resolv.conf

# enp7s2 (локальная сеть)
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "192.168.3.1/28" > /etc/net/ifaces/enp7s2/ipv4address

systemctl restart network

echo "Настройка BR-RTR завершена."

echo "=== Настройка BR-RTR: интернет, время ==="

# --- IP Forwarding ---
sed -i '/^net.ipv4.ip_forward/d' /etc/net/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf
sysctl -p
systemctl restart network

# --- Установка и настройка iptables ---
apt-get update && apt-get install -y iptables

iptables -t nat -A POSTROUTING -o enp7s1 -s 192.168.3.0/28 -j MASQUERADE
iptables -A FORWARD -i ens19 -o enp7s1 -s 192.168.3.0/28 -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables --now
systemctl restart iptables
systemctl status iptables --no-pager
iptables -t nat -L -n -v

# --- Часовой пояс (tzdata) ---
#apt-get install -y tzdata
#timedatectl set-timezone Europe/Moscow
#timedatectl

echo "BR-RTR: настройка завершена."


echo "=== Настройка GRE-туннеля на BR-RTR ==="

mkdir -p /etc/net/ifaces/gre1

cat > /etc/net/ifaces/gre1/options <<EOF
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.2.2
TUNREMOTE=172.16.1.2
TUNOPTIONS='ttl 64'
EOF

echo "10.10.0.2/30" > /etc/net/ifaces/gre1/ipv4address

systemctl restart network

echo "GRE-туннель на BR-RTR настроен."

echo "=== Настройка DNS-клиента на BR-RTR ==="

# Замена DNS-сервера на интерфейсе enp7s1
echo "nameserver 192.168.100.2" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network

echo "DNS-клиент на BR-RTR обновлён."

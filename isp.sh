#!/bin/bash
set -e

echo "=== Настройка ISP ==="

# hostname
hostnamectl set-hostname isp.au-team.irpo

# Создание каталогов интерфейсов
mkdir -p /etc/net/ifaces/enp7s2
mkdir -p /etc/net/ifaces/enp7s3

# enp7s2
cat > /etc/net/ifaces/enp7s2/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "172.16.1.1/28" > /etc/net/ifaces/enp7s2/ipv4address

# enp7s3
cat > /etc/net/ifaces/enp7s3/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "172.16.2.1/28" > /etc/net/ifaces/enp7s3/ipv4address

# Перезапуск сети
systemctl restart network

echo "Настройка ISP завершена."


echo "=== Настройка ISP: интернет, время ==="

# --- IP Forwarding ---
sed -i '/^net.ipv4.ip_forward/d' /etc/net/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf
sysctl -p
systemctl restart network

# --- Установка и настройка iptables ---
apt-get update && apt-get install -y iptables

iptables -t nat -A POSTROUTING -o enp7s1 -s 172.16.1.0/28 -j MASQUERADE
iptables -t nat -A POSTROUTING -o enp7s1 -s 172.16.2.0/28 -j MASQUERADE
iptables -A FORWARD -i ens19 -o enp7s1 -s 172.16.1.0/28 -j ACCEPT
iptables -A FORWARD -i ens20 -o enp7s1 -s 172.16.2.0/28 -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables --now
systemctl restart iptables
systemctl status iptables --no-pager
iptables -t nat -L -n -v

# --- Часовой пояс (tzdata) ---
#apt-get install -y tzdata
#timedatectl set-timezone Europe/Moscow
#timedatectl

echo "ISP: настройка завершена."


echo "=== Установка и настройка chrony (NTP-сервер) на ISP ==="

# Установка chrony
apt-get update && apt-get install -y chrony

# Резервное копирование оригинального конфига (если ещё не сделано)
[ -f /etc/chrony.conf ] && cp -n /etc/chrony.conf /etc/chrony.conf.bak

# Конфигурация chrony
cat > /etc/chrony.conf <<'EOF'
# Внешние источники времени
pool 2.alt.pool.ntp.org iburst
pool 3.alt.pool.ntp.org iburst

# Разрешить доступ клиентам из локальных сетей ISP
allow 172.16.1.0/28
allow 172.16.2.0/28

# Локальные настройки
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony/chrony.keys
leapsectz right/UTC
logdir /var/log/chrony
EOF

# Включение и запуск службы
systemctl enable --now chronyd
systemctl restart chronyd
systemctl status chronyd --no-pager

echo "Chrony на ISP настроен. Проверка: chronyc sources -v"

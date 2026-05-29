#!/bin/bash
set -e

echo "=== Настройка HQ-SRV ==="

# hostname
hostnamectl set-hostname hq-srv.au-team.irpo

# Каталог интерфейса enp7s1 (если отсутствует)
mkdir -p /etc/net/ifaces/enp7s1

# Статическая конфигурация взамен DHCP
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "192.168.100.2/27" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 192.168.100.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 9.9.9.9" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network

echo "Настройка HQ-SRV завершена."


echo "=== Настройка HQ-SRV: время, SSH ==="

# --- Часовой пояс (без установки tzdata – уже есть) ---
#timedatectl set-timezone Europe/Moscow
#timedatectl

# --- Создание пользователя sshuser ---
groupadd -f wheel
useradd sshuser -u 2026 -U
echo "sshuser:P@ssw0rd" | chpasswd
usermod -a -G wheel sshuser

# --- Права sudo без пароля ---
cat > /etc/sudoers.d/sshuser <<EOF
sshuser ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/sshuser

echo "Пользователь sshuser создан. Проверьте: sudo cat /root/.bashrc"


echo "=== Настройка SSH-сервера на HQ-SRV ==="

apt-get update && apt-get install -y openssh-server

ensure_sshd_config() {
    local key="$1" val="$2"
    if grep -q "^${key} " /etc/openssh/sshd_config; then
        sed -i "s/^${key} .*/${key} ${val}/" /etc/openssh/sshd_config
    else
        echo "${key} ${val}" >> /etc/openssh/sshd_config
    fi
}

ensure_sshd_config Port 2026
ensure_sshd_config MaxAuthTries 2
ensure_sshd_config Banner /etc/openssh/sshd_banner
ensure_sshd_config AllowUsers sshuser

cat > /etc/openssh/sshd_banner <<EOF
Authorized access only
EOF

systemctl enable sshd --now
systemctl restart sshd

systemctl status sshd --no-pager

echo "SSH на HQ-SRV настроен."


echo "=== Настройка DNS-сервера на HQ-SRV ==="

# Установка пакетов
apt-get update && apt-get install -y bind nano

# --- Конфигурация BIND ---
# options.conf
cat > /etc/bind/options.conf <<EOF
options {
	version "unknown";
	directory "/etc/bind/zone";
	dump-file "/var/run/named/named_dump.db";
	statistics-file "/var/run/named/named.stats";
	recursing-file "/var/run/named/named.recursing";
	secroots-file "/var/run/named/named.secroots";
listen-on { any; };
forward first;
forwarders { 9.9.9.9; };
allow-query { any; };
EOF

# local.conf с зонами
cat > /etc/bind/local.conf <<EOF
// Add other zones here

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
cat > /etc/bind/db.au-team.irpo <<EOF
\$TTL 86400
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
cat > /etc/bind/db.192.168.100 <<EOF
\$TTL 86400
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
cat > /etc/bind/db.192.168.200.64 <<EOF
\$TTL 86400
@   IN  SOA hq-srv.au-team.irpo. root.au-team.irpo. (
        2025121001
        3600
        1800
        604800
        86400 )

    IN  NS  hq-srv.au-team.irpo.

1  IN  PTR  hq-cli.au-team.irpo.
EOF

# --- Настройка локального резолвера ---
# Удаляем старый resolv.conf интерфейса (если есть)
rm -f /etc/net/ifaces/enp7s1/resolv.conf
systemctl restart network

# Указываем использовать локальный DNS
cat > /etc/resolvconf.conf <<EOF
name_servers=127.0.0.1
EOF

resolvconf -u
systemctl restart network

# --- Запуск и активация BIND ---
systemctl enable --now bind
systemctl restart bind
systemctl status bind --no-pager

echo "DNS-сервер на HQ-SRV настроен."

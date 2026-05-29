#!/bin/bash
set -e

echo "=== Настройка BR-SRV ==="

# hostname
hostnamectl set-hostname br-srv.au-team.irpo

# Каталог интерфейса enp7s1
mkdir -p /etc/net/ifaces/enp7s1

# Статическая конфигурация взамен DHCP
cat > /etc/net/ifaces/enp7s1/options <<EOF
BOOTPROTO=static
TYPE=eth
EOF
echo "192.168.3.2/28" > /etc/net/ifaces/enp7s1/ipv4address
echo "default via 192.168.3.1" > /etc/net/ifaces/enp7s1/ipv4route
echo "nameserver 9.9.9.9" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network

echo "Настройка BR-SRV завершена."


echo "=== Настройка BR-SRV: время, SSH ==="

# --- Часовой пояс ---
timedatectl set-timezone Asia/Novosibirsk
timedatectl

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


echo "=== Настройка SSH-сервера на BR-SRV ==="

# Установка openssh-server
apt-get update && apt-get install -y openssh-server

# Функция для безопасной замены/добавления параметра в sshd_config
ensure_sshd_config() {
    local key="$1" val="$2"
    if grep -q "^${key} " /etc/openssh/sshd_config; then
        sed -i "s/^${key} .*/${key} ${val}/" /etc/openssh/sshd_config
    else
        echo "${key} ${val}" >> /etc/openssh/sshd_config
    fi
}

# Настройка параметров
ensure_sshd_config Port 2026
ensure_sshd_config MaxAuthTries 2
ensure_sshd_config Banner /etc/openssh/sshd_banner
ensure_sshd_config AllowUsers sshuser

# Создание баннера
cat > /etc/openssh/sshd_banner <<EOF
Authorized access only
EOF

# Включение и перезапуск службы
systemctl enable sshd --now
systemctl restart sshd

# Проверка статуса (без пагера)
systemctl status sshd --no-pager

echo "SSH на BR-SRV настроен."


echo "=== Настройка DNS-клиента на BR-RTR ==="

# Замена DNS-сервера на интерфейсе enp7s1
echo "nameserver 192.168.100.2" > /etc/net/ifaces/enp7s1/resolv.conf

systemctl restart network

echo "DNS-клиент на BR-RTR обновлён."

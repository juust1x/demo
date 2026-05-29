bash#!/bin/bash

# 1. Установка пакетов chrony и apt-get (для управления пакетами в ALT Linux)
echo "Установка Chrony..."
apt-get update
apt-get install -y chrony

# 2. Базовая настройка: добавление серверов точного времени (вы можете указать свои пулы)
cat << 'EOF' > /etc/chrony.conf
pool pool.ntp.org iburst
driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
allow 127.0.0.1
bindcmdaddress 127.0.0.1
keyfile /etc/chrony/chrony.keys
commandkey 1
generatecommandkey
noclientlog
logchange 0.5
logdir /var/log/chrony
EOF

# 3. Добавление службы в автозагрузку и перезапуск демона
echo "Запуск и включение Chrony..."
systemctl enable --now chronyd

# 4. Проверка текущего статуса и источников
echo "Проверка статуса Chrony..."
chronyc sources -v

echo "Настройка завершена!"

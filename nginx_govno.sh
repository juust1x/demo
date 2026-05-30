#!/bin/sh

echo "Установка Nginx"
apt-get update && apt-get install nginx -y
systemctl enable --now nginx.service

echo "Создание конфигурации"
mkdir -p /etc/nginx/sites-available.d
cat > /etc/nginx/sites-available.d/site.conf <<EOF
server {
    listen 80;
    server_name localhost .local 10.0.2.11;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location / {
        root /var/www/html/;
        autoindex on;
    }
}
EOF

echo "Активация конфига"
mkdir -p /etc/nginx/sites-enabled.d
ln -sf /etc/nginx/sites-available.d/site.conf /etc/nginx/sites-enabled.d/

echo "Создание веб-контента"
mkdir -p /var/www/html
cat > /var/www/html/index.html <<EOF
<html>
<body>
<h1>It works! Nginx</h1>
</body>
</html>
EOF

systemctl restart nginx.service
rm -rf /root/nginx.sh
apt-get remove git -y
history -c  




#!/bin/bash
mkdir -p /nginx/data /nginx/templates
rm -rf /data /etc/nginx/templates
ln -sf /nginx/data /data
ln -sf /nginx/templates /etc/nginx/templates
watch-nginx-config.sh /etc/nginx/templates &
exec /usr/sbin/sshd

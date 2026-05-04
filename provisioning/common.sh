#!/usr/bin/env bash
# aiwiki :: common provisioning
# Запускается на каждой ВМ при первом vagrant up.
# Идемпотентен — можно запускать повторно.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== aiwiki :: common provisioning on $(hostname) ==="

# 1. Обновление пакетной базы и базовый набор утилит
apt-get update -qq
apt-get install -y -qq \
    curl wget vim htop tmux unzip jq \
    ca-certificates gnupg \
    avahi-daemon avahi-utils libnss-mdns

# 2. Часовой пояс — чтобы логи были читаемые
timedatectl set-timezone Europe/Moscow || true

# 3. Avahi — анонс <hostname>.local в локалку через mDNS
systemctl enable --now avahi-daemon

# 4. NSS-конфиг — чтобы getaddrinfo резолвил .local через mDNS
#    (libnss-mdns обычно сам прописывает, но проверим)
if ! grep -q "mdns4_minimal" /etc/nsswitch.conf; then
    sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns mdns4/' \
        /etc/nsswitch.conf
fi

echo "=== Provisioning done on $(hostname) ==="

#!/usr/bin/env bash
# aiwiki :: postgres provisioning
# Запускается только на aiwiki-pg.
# Идемпотентен — можно запускать повторно через `vagrant provision aiwiki-pg`.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== aiwiki :: postgres provisioning on $(hostname) ==="

# 1. Установка PostgreSQL (14 в Ubuntu 22.04 по умолчанию).
#    Достаточная версия для n8n / Wiki.js / chat memory.
apt-get update -qq
apt-get install -y -qq postgresql postgresql-contrib

# Определяем версию (нужна для путей конфигов: /etc/postgresql/<v>/main/)
PG_VERSION=$(ls /etc/postgresql 2>/dev/null | sort -nr | head -1)
if [[ -z "${PG_VERSION}" ]]; then
    echo "[postgres] ERROR: /etc/postgresql/<version>/ не появилась после apt install"
    exit 1
fi
PG_DIR="/etc/postgresql/${PG_VERSION}/main"
echo "[postgres] working with version ${PG_VERSION} at ${PG_DIR}"

# 2. listen_addresses = '*' — слушаем на всех интерфейсах
#    (включая eth1 в 192.168.1.0/24, через который к нам ходят остальные ВМ)
if ! grep -qE "^listen_addresses\s*=\s*'\*'" "${PG_DIR}/postgresql.conf"; then
    sed -i "s/^#*listen_addresses\s*=.*/listen_addresses = '*'/" "${PG_DIR}/postgresql.conf"
    echo "[postgres] postgresql.conf: listen_addresses = '*'"
fi

# 3. pg_hba.conf — доступ строго из 192.168.1.0/24, по парам db/user.
#    Маркер используем чтобы блок добавлялся ровно один раз.
HBA="${PG_DIR}/pg_hba.conf"
HBA_MARKER="# aiwiki :: lab access (192.168.1.0/24)"

if ! grep -qF "${HBA_MARKER}" "${HBA}"; then
    cat >> "${HBA}" <<EOF

${HBA_MARKER}
host    n8n             n8n_user        192.168.1.0/24          scram-sha-256
host    wikijs          wikijs_user     192.168.1.0/24          scram-sha-256
host    agent_memory    agent_user      192.168.1.0/24          scram-sha-256
EOF
    echo "[postgres] pg_hba.conf: aiwiki rules appended"
fi

# 4. Применяем конфиг (рестарт нужен из-за смены listen_addresses;
#    pg_hba.conf по-хорошему достаточно reload, но рестарт безопаснее)
systemctl restart postgresql

# 5. Ждём, пока сервер примет соединения
for i in {1..30}; do
    if sudo -u postgres pg_isready -q; then break; fi
    sleep 1
done

# 6. Применяем init.sql (предварительно скопирован Vagrant'ом в /tmp/)
sudo -u postgres psql -v ON_ERROR_STOP=1 -f /tmp/aiwiki-init.sql

echo "=== Provisioning done on $(hostname) ==="

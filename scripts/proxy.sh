#!/usr/bin/env bash
#
# proxy.sh — поднимает/опускает SSH-туннель + Privoxy для скачиваний
# через VPS, обходя блокировки домашнего провайдера.
#
# Состав:
#   ssh -D <SOCKS_PORT>  поднимает SOCKS5-прокси на localhost
#   Privoxy на :8118     преобразует SOCKS5 в HTTP-прокси
#                        (Vagrant/apt/docker и пр. SOCKS не умеют, HTTP — да)
#
# Использование:
#   ./scripts/proxy.sh up           — поднять туннель + privoxy
#   ./scripts/proxy.sh down         — опустить
#   ./scripts/proxy.sh status       — показать состояние и внешний IP
#   ./scripts/proxy.sh env          — печать env-переменных для eval
#   ./scripts/proxy.sh run CMD      — выполнить CMD с прокси-env
#
# Конфиг — файл scripts/.env-proxy рядом со скриптом (см. .env-proxy.example).
# Файл в .gitignore, потому что содержит IP/имя VPS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загружаем конфиг, если есть
if [[ -f "${SCRIPT_DIR}/.env-proxy" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env-proxy"
fi

# Дефолты
PROXY_HOST="${PROXY_HOST:-}"
PROXY_USER="${PROXY_USER:-}"
PROXY_SSH_PORT="${PROXY_SSH_PORT:-22}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
HTTP_PORT="${HTTP_PORT:-8118}"

PROXY_URL="http://127.0.0.1:${HTTP_PORT}"
NO_PROXY_LIST="localhost,127.0.0.1,::1,192.168.1.0/24,*.local"

ssh_running() {
    pgrep -f "ssh -D ${SOCKS_PORT}.*${PROXY_HOST}" >/dev/null 2>&1
}

privoxy_running() {
    systemctl is-active --quiet privoxy 2>/dev/null
}

require_config() {
    if [[ -z "${PROXY_HOST}" || -z "${PROXY_USER}" ]]; then
        echo "ERROR: PROXY_HOST и PROXY_USER не заданы." >&2
        echo "Скопируй scripts/.env-proxy.example в scripts/.env-proxy и заполни." >&2
        exit 1
    fi
}

ensure_privoxy_installed() {
    if ! command -v privoxy >/dev/null 2>&1; then
        echo "[proxy] privoxy не установлен — ставим"
        sudo apt-get update -qq
        sudo apt-get install -y -qq privoxy
    fi
}

ensure_privoxy_configured() {
    local snippet="forward-socks5 / 127.0.0.1:${SOCKS_PORT} ."
    local cfg=/etc/privoxy/config
    if ! grep -qF "${snippet}" "${cfg}"; then
        echo "[proxy] добавляем forward-socks5 в ${cfg}"
        echo "${snippet}" | sudo tee -a "${cfg}" >/dev/null
        sudo systemctl restart privoxy 2>/dev/null || true
    fi
}

cmd_up() {
    require_config
    ensure_privoxy_installed
    ensure_privoxy_configured

    if ssh_running; then
        echo "[proxy] ssh tunnel: уже поднят"
    else
        echo "[proxy] поднимаем ssh -D ${SOCKS_PORT} → ${PROXY_USER}@${PROXY_HOST}:${PROXY_SSH_PORT}"
        ssh -D "${SOCKS_PORT}" -N -f \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -p "${PROXY_SSH_PORT}" \
            "${PROXY_USER}@${PROXY_HOST}"
    fi

    if ! privoxy_running; then
        sudo systemctl start privoxy
    fi

    # Проверяем
    sleep 1
    local ext
    ext=$(curl -x "${PROXY_URL}" -s --max-time 10 https://ifconfig.me 2>/dev/null || echo "")
    if [[ -n "$ext" ]]; then
        echo "[proxy] OK · внешний IP через прокси: ${ext}"
        echo
        echo "Используй так:"
        echo "  eval \"\$(${0} env)\"   # для текущей сессии"
        echo "  ${0} run vagrant box add generic/ubuntu2204 --provider=libvirt"
    else
        echo "[proxy] WARN: прокси не отвечает на :${HTTP_PORT}"
        echo "Проверь: systemctl status privoxy; ss -tlnp | grep ${SOCKS_PORT}"
        exit 1
    fi
}

cmd_down() {
    if ssh_running; then
        pkill -f "ssh -D ${SOCKS_PORT}.*${PROXY_HOST}" || true
        echo "[proxy] ssh tunnel остановлен"
    else
        echo "[proxy] ssh tunnel и так не запущен"
    fi

    if privoxy_running; then
        sudo systemctl stop privoxy
        echo "[proxy] privoxy остановлен"
    fi
}

cmd_status() {
    if ssh_running; then
        echo "[proxy] ssh tunnel: UP   (socks5://127.0.0.1:${SOCKS_PORT})"
    else
        echo "[proxy] ssh tunnel: DOWN"
    fi

    if privoxy_running; then
        echo "[proxy] privoxy:     UP   (http://127.0.0.1:${HTTP_PORT})"
    else
        echo "[proxy] privoxy:     DOWN"
    fi

    if ssh_running && privoxy_running; then
        local ext
        ext=$(curl -x "${PROXY_URL}" -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
        echo "[proxy] internet:    ${ext:-(не отвечает)}"
    fi
}

cmd_env() {
    cat <<EOF
export HTTPS_PROXY="${PROXY_URL}"
export HTTP_PROXY="${PROXY_URL}"
export https_proxy="${PROXY_URL}"
export http_proxy="${PROXY_URL}"
export NO_PROXY="${NO_PROXY_LIST}"
export no_proxy="${NO_PROXY_LIST}"
EOF
}

cmd_run() {
    if ! ssh_running || ! privoxy_running; then
        echo "[proxy] прокси не запущен — выполни '${0} up' сначала" >&2
        exit 1
    fi
    if [[ $# -eq 0 ]]; then
        echo "Usage: ${0} run <command> [args...]" >&2
        exit 1
    fi
    HTTPS_PROXY="${PROXY_URL}" \
    HTTP_PROXY="${PROXY_URL}" \
    https_proxy="${PROXY_URL}" \
    http_proxy="${PROXY_URL}" \
    NO_PROXY="${NO_PROXY_LIST}" \
    no_proxy="${NO_PROXY_LIST}" \
        "$@"
}

usage() {
    cat <<EOF
Usage: $0 {up|down|status|env|run <cmd>...}

Commands:
  up      Поднять SSH-туннель и Privoxy
  down    Опустить туннель и остановить Privoxy
  status  Показать состояние + внешний IP через прокси
  env     Напечатать export-команды (eval "\$($0 env)")
  run     Выполнить команду с прокси-env

Config: scripts/.env-proxy (см. .env-proxy.example)
EOF
}

case "${1:-}" in
    up)     cmd_up ;;
    down)   cmd_down ;;
    status) cmd_status ;;
    env)    cmd_env ;;
    run)    shift; cmd_run "$@" ;;
    *)      usage; exit 1 ;;
esac

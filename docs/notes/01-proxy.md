# SSH-tunnel + Privoxy для обхода блокировок

В РФ ряд ресурсов недоступен напрямую — `vagrantcloud.com`, `gems.hashicorp.com`, иногда `docker.io`, `gcr.io`, и др. Для таких случаев у нас есть помощник `scripts/proxy.sh`, который поднимает SSH-туннель до VPS и преобразует его в HTTP-прокси через Privoxy. Vagrant, apt, docker, git — все умеют ходить через `HTTPS_PROXY`/`HTTP_PROXY`.

## Как устроено

```
[ pc-host ]                              [ VPS ]
                                          
команда → HTTP_PROXY=:8118               
            ↓                            
        Privoxy :8118                    
            ↓ SOCKS5                     
        ssh -D :1080  ──────────────►  sshd :22 ──► интернет
            ↑                            
        TCP-туннель внутри ssh           
```

Преимущества такого подхода: TCP/22 редко режется провайдером, не нужны нестандартные клиенты, ничего не меняется в маршрутах системы (default route остаётся на роутер), `apt`/`vagrant`/`docker` с `HTTPS_PROXY` ходят корректно.

Ограничения: только TCP. UDP в этот туннель не пойдёт (это редко нужно для скачивания пакетов).

## Первоначальная настройка

```bash
cp scripts/.env-proxy.example scripts/.env-proxy
vim scripts/.env-proxy
# заполнить PROXY_HOST, PROXY_USER, PROXY_SSH_PORT
```

В VPS должен быть SSH-доступ по ключу (через пароль будет запрашивать каждый запуск, неудобно). Залить публичный ключ pc-host:

```bash
ssh-copy-id -p <ssh_port> <user>@<vps_host>
```

## Использование

```bash
# Поднять туннель + privoxy
./scripts/proxy.sh up

# Проверить, что прокси отвечает (должен показать IP VPS)
./scripts/proxy.sh status

# Запустить любую команду через прокси
./scripts/proxy.sh run vagrant box add generic/ubuntu2204 --provider=libvirt
./scripts/proxy.sh run apt-cache search foo

# Или экспортировать env в текущий shell
eval "$(./scripts/proxy.sh env)"
vagrant box add ...
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy NO_PROXY no_proxy

# Опустить
./scripts/proxy.sh down
```

`NO_PROXY` автоматически включает `localhost`, `127.0.0.1`, `192.168.1.0/24`, `*.local` — чтобы локалка не ходила через VPS.

## Что делать если упало

```bash
./scripts/proxy.sh status              # внешний IP должен быть VPS-овским
ss -tlnp | grep -E '1080|8118'         # должны слушать ssh и privoxy
systemctl status privoxy
journalctl -u privoxy -n 30
pgrep -af "ssh -D"                     # ssh-туннель запущен?
```

Если ssh упал (например, по таймауту) — `./scripts/proxy.sh down && ./scripts/proxy.sh up`.

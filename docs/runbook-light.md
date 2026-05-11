# Runbook · Light

Пошаговая инструкция запуска и проверки уровня Light. Будет наполняться по мере прохождения этапов.

## Предусловия

- ПК с установленной Ubuntu Server 24.04 LTS
- KVM/libvirt + Vagrant + плагин `vagrant-libvirt`
- Мост `br0` поверх физического Ethernet
- Avahi-демон для mDNS
- IP `192.168.1.10` зарезервирован за хостом на роутере

## Запуск с нуля

*(будет дописано по итогу этапа 8)*

```bash
git clone https://github.com/dazila/aiwiki.git
cd aiwiki
vagrant up
```

## Проверки

### Этап 1 — ВМ поднимаются и видят друг друга

*(будет дописано)*

### Этап 2 — PostgreSQL доступен из подсети

После `vagrant provision aiwiki-pg` (или `vagrant up` на чистой машине) проверка:

```bash
# С aiwiki-n8n: подключаемся к каждой из трёх БД по сети
vagrant ssh aiwiki-n8n -c "
    apt list --installed 2>/dev/null | grep -q postgresql-client || sudo apt-get install -y postgresql-client
    PGPASSWORD=n8n_pass_light    psql -h 192.168.1.20 -U n8n_user    -d n8n          -c 'SELECT current_database(), current_user;'
    PGPASSWORD=wikijs_pass_light psql -h 192.168.1.20 -U wikijs_user -d wikijs       -c 'SELECT current_database(), current_user;'
    PGPASSWORD=agent_pass_light  psql -h 192.168.1.20 -U agent_user  -d agent_memory -c 'SELECT current_database(), current_user;'
"
```

Каждый запрос должен вернуть имя БД и имя пользователя.

Дополнительно — отказ извне подсети:

```bash
# С мака (192.168.1.X): подключение должно работать
psql -h aiwiki-pg.local -U n8n_user -d n8n  # пароль: n8n_pass_light

# С хоста pc-host (192.168.121.X через mgmt) — не должно работать,
# потому что pg_hba.conf разрешает только 192.168.1.0/24.
```

### Этап 3 — n8n хранит данные в Postgres

*(будет дописано)*

### Этап 4 — Ollama отвечает

*(будет дописано)*

### Этап 5 — AI Agent работает

*(будет дописано)*

### Этап 6 — память агента переживает рестарт

*(будет дописано)*

### Этап 7 — Wiki.js на Postgres со страницей схемы

*(будет дописано)*

### Этап 8 — финальный smoke

*(будет дописано)*

## Типовые проблемы

*(будет наполняться по факту)*

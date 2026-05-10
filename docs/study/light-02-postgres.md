# Light · Этап 2 — PostgreSQL

## Exam guide (компетенции)

К концу этапа ты должен уметь и понимать:

**Архитектура и понятия PostgreSQL**
- объяснить разницу между cluster, database, schema, role, user;
- описать, что такое «owner» базы данных и какие у него привилегии;
- знать, где лежат конфиги и данные PG в Ubuntu (`/etc/postgresql/<v>/main/`, `/var/lib/postgresql/<v>/main/`).

**Конфигурация: postgresql.conf и pg_hba.conf**
- объяснить разницу между этими двумя файлами;
- знать, что меняется через `reload` (SIGHUP), а что требует `restart`;
- знать, что `listen_addresses` требует restart, а правки `pg_hba.conf` достаточно reload;
- читать строку `pg_hba.conf` (TYPE, DATABASE, USER, ADDRESS, METHOD) и объяснять, что она разрешает.

**Аутентификация**
- знать методы: `trust`, `password`, `md5`, `scram-sha-256`, `peer`, `ident`, `cert`;
- объяснить, чем `scram-sha-256` лучше `md5`;
- объяснить, что такое `peer` и почему `sudo -u postgres psql` работает без пароля;
- понимать, почему порядок строк в `pg_hba.conf` важен (правило first-match-wins).

**Идемпотентный SQL**
- знать конструкции `IF NOT EXISTS`, `DO $$ ... END $$`, `\gexec`;
- знать ограничение, что `CREATE DATABASE` не работает в транзакции / в `DO`-блоке.

**Привилегии**
- знать `GRANT ... ON DATABASE`, `GRANT ... ON SCHEMA public`;
- знать, что в PG 15+ нужно явно давать право `CREATE ON SCHEMA public`, иначе пользователь не сможет создавать таблицы в своей же базе.

**Эксплуатация**
- запускать/перезапускать сервис: `systemctl restart postgresql`;
- проверять готовность: `pg_isready`;
- базовые команды psql: `\l`, `\du`, `\dn`, `\dt`, `\c`, `\q`;
- подключаться удалённо: `psql -h <host> -U <user> -d <db>`, `PGPASSWORD=...`.

## Темы и краткое summary

### 1. Архитектура: cluster → database → schema → table

В PostgreSQL **cluster** (кластер) — это набор баз данных, обслуживаемых одним сервером (одним процессом `postgres`). Внутри кластера живёт несколько **databases** (баз). Внутри каждой базы — несколько **schemas** (по умолчанию схема `public`). Внутри схемы — таблицы, индексы, функции и т.п. **Roles** (роли) и привилегии — глобальные на уровне кластера, не базы. То есть `n8n_user` в нашей схеме — это роль кластера, у которой есть права на конкретную базу `n8n`.

«Cluster» в терминологии PG — это не «кластер из нескольких серверов» (как в MySQL Cluster), а «один сервер с набором баз». Многосерверный сетап в PG называется replication / sharding.

В Ubuntu файлы кластера лежат в `/var/lib/postgresql/<version>/main/` (данные) и `/etc/postgresql/<version>/main/` (конфиги). Сервис называется `postgresql@<version>-main.service`, оборачивается в общий `postgresql.service`.

### 2. postgresql.conf vs pg_hba.conf

Два главных конфигурационных файла:

- **`postgresql.conf`** — настройки сервера: на каком интерфейсе слушать, какой порт, сколько памяти под буферы, логирование, репликация.
- **`pg_hba.conf`** — Host-Based Authentication, «кто откуда каким методом может подключаться». Это файл правил вида:

```
TYPE   DATABASE   USER   ADDRESS         METHOD
host   n8n        n8n_user   192.168.1.0/24   scram-sha-256
```

Порядок строк важен: PG проверяет сверху вниз, первое совпадение — использует. Это очень частая ловушка: добавил строгое правило в конец, а сверху уже стоит `host all all 0.0.0.0/0 trust` — никакой защиты не получилось.

Перечитываются конфиги по-разному. Большинство параметров `postgresql.conf` и весь `pg_hba.conf` — через **reload** (`pg_ctl reload` или `SELECT pg_reload_conf();` или `systemctl reload postgresql`, посылается `SIGHUP`). Часть параметров (`listen_addresses`, `shared_buffers`, `port`) — только через **restart**.

### 3. Аутентификация в pg_hba.conf

Колонка METHOD определяет, как PG проверяет подключение. Самые важные:

- **`trust`** — пускать без проверки. Опасно. Используется иногда для local-сокета, никогда для сети.
- **`password`** — пароль в открытом виде по сети. Не использовать никогда.
- **`md5`** — challenge-response с MD5-хешем. Раньше стандарт, сейчас устарел: при утечке `pg_authid` злоумышленник получает хеш, который равен паролю с точки зрения протокола (можно логиниться без знания пароля).
- **`scram-sha-256`** — SCRAM с SHA-256, RFC 7677. Современный стандарт. Хранит хеш так, что даже при утечке `pg_authid` злоумышленник не может логиниться без знания пароля или без полного перебора. **Используем.**
- **`peer`** — для local-сокета: PG смотрит uid процесса, который пытается подключиться, и пускает, если есть PG-роль с тем же именем. Поэтому `sudo -u postgres psql` работает без пароля: процесс от имени `postgres`, есть роль `postgres`, метод `peer` пускает.
- **`ident`** — то же что peer, но через RFC 1413 (старый протокол, почти не используется).
- **`cert`** — клиентский сертификат TLS. Нужно `hostssl`. Это уровень Expert.

TYPE: `local` — Unix-сокет, `host` — TCP с/без TLS, `hostssl` — только TLS, `hostnossl` — только без TLS.

### 4. Идемпотентный SQL

Идемпотентность init-скрипта — это когда повторный запуск не падает с ошибкой и оставляет систему в том же состоянии. Для PG:

```sql
-- Создание роли — DO-блок:
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'foo') THEN
        CREATE USER foo WITH PASSWORD 'bar';
    END IF;
END $$;
```

Здесь `DO $$ ... $$` — анонимный PL/pgSQL-блок, нечто вроде однократной анонимной функции.

`CREATE DATABASE` нельзя засунуть в `DO`-блок: он не работает в транзакциях, а PL/pgSQL всегда в транзакции. Поэтому используется приём `\gexec` в psql:

```sql
SELECT 'CREATE DATABASE foo OWNER foo'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'foo')\gexec
```

`\gexec` — meta-команда psql: «возьми результат предыдущего SELECT (текстовую строку) и выполни как SQL». Если SELECT вернул 0 строк — нечего исполнять, и команда тихо проходит.

### 5. Привилегии и schema public

`GRANT ALL PRIVILEGES ON DATABASE foo TO foo_user` даёт пользователю полные права над базой как объектом (CONNECT, CREATE schemas, TEMPORARY tables). Но это не даёт права создавать таблицы в существующих схемах, в частности в `public`.

В PG 14 и раньше схема `public` имела `GRANT ALL TO PUBLIC` по умолчанию — то есть любой подключившийся мог создавать в ней таблицы. **В PG 15+ это убрали** (CVE-2018-1058) — теперь нужен явный grant:

```sql
GRANT ALL ON SCHEMA public TO foo_user;
```

Иначе при попытке `CREATE TABLE foo (...)` пользователь получит `permission denied for schema public`.

### 6. Базовая эксплуатация

Запуск/перезапуск:
```bash
sudo systemctl status postgresql
sudo systemctl restart postgresql        # для listen_addresses, port, shared_buffers
sudo systemctl reload postgresql         # для большинства параметров и pg_hba.conf
```

Проверка готовности:
```bash
pg_isready                               # вернёт «accepting connections» или нет
pg_isready -h 192.168.1.20 -p 5432       # удалённо
```

Подключение к psql:
```bash
sudo -u postgres psql                    # локально через peer
psql -h aiwiki-pg.local -U n8n_user -d n8n   # удалённо, попросит пароль
PGPASSWORD=... psql -h ... -U ... -d ...     # в скриптах
```

Команды psql:
```
\l         список баз
\du        список ролей
\dn        список схем
\dt        список таблиц текущей схемы
\c db      переключиться на базу
\q         выйти
```

## Источники для углублённого чтения

Не нужно читать всё — ходи по ссылкам по мере необходимости.

**Официальная документация PostgreSQL 14:**
- Архитектура и concepts — https://www.postgresql.org/docs/14/tutorial-arch.html
- pg_hba.conf — https://www.postgresql.org/docs/14/auth-pg-hba-conf.html (главное)
- Authentication methods — https://www.postgresql.org/docs/14/auth-methods.html
- postgresql.conf и параметры — https://www.postgresql.org/docs/14/runtime-config.html
- Roles and privileges — https://www.postgresql.org/docs/14/user-manag.html и https://www.postgresql.org/docs/14/ddl-priv.html
- DO statement — https://www.postgresql.org/docs/14/sql-do.html
- psql meta-commands (включая \gexec) — https://www.postgresql.org/docs/14/app-psql.html

**Про PG 15 schema public CVE:**
- https://www.postgresql.org/about/news/postgresql-15-released-2526/ (раздел «Public Schema Permission Changes»)

**Полезные блоги:**
- «Demystifying schemas & search_path through examples» — https://www.crunchydata.com/blog/demystifying-schemas-search_path-through-examples
- «Idempotent PostgreSQL DDL scripts» — обычный поиск, много хороших постов

## Ключевые термины (для глоссария)

cluster, database, schema, role, user, owner, GRANT, REVOKE, search_path, public schema, pg_hba.conf, postgresql.conf, listen_addresses, scram-sha-256, md5, peer, trust, hostssl, idempotent, DO block, \gexec, pg_isready, psql, SIGHUP, reload, restart.

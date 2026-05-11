-- aiwiki :: PostgreSQL init
-- Создаёт три базы и трёх пользователей с минимальными правами.
--
-- Light-уровень: пароли зафиксированы в открытом виде. На Normal-уровне
-- они переедут в Ansible Vault, провижининг будет шаблонизировать init.sql
-- через jinja2.
--
-- Скрипт идемпотентный — можно запускать повторно без ошибок.

-- ===========================================
-- Пользователи
-- ===========================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n_user') THEN
        CREATE USER n8n_user WITH PASSWORD 'n8n_pass_light';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'wikijs_user') THEN
        CREATE USER wikijs_user WITH PASSWORD 'wikijs_pass_light';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'agent_user') THEN
        CREATE USER agent_user WITH PASSWORD 'agent_pass_light';
    END IF;
END $$;

-- ===========================================
-- Базы данных (CREATE DATABASE не работает в DO/транзакции, поэтому через \gexec)
-- ===========================================
SELECT 'CREATE DATABASE n8n OWNER n8n_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

SELECT 'CREATE DATABASE wikijs OWNER wikijs_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'wikijs')\gexec

SELECT 'CREATE DATABASE agent_memory OWNER agent_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'agent_memory')\gexec

-- ===========================================
-- Привилегии
-- ===========================================
GRANT ALL PRIVILEGES ON DATABASE n8n          TO n8n_user;
GRANT ALL PRIVILEGES ON DATABASE wikijs       TO wikijs_user;
GRANT ALL PRIVILEGES ON DATABASE agent_memory TO agent_user;

-- В PG 15+ для создания таблиц в схеме public нужны явные grant'ы на public.
-- Делаем отдельно для каждой базы — переключаемся через \c.
\c n8n
GRANT ALL ON SCHEMA public TO n8n_user;

\c wikijs
GRANT ALL ON SCHEMA public TO wikijs_user;

\c agent_memory
GRANT ALL ON SCHEMA public TO agent_user;

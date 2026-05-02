# Архитектура

## Контекст

Внутренний AI-агент, который отвечает сотрудникам на вопросы об инфраструктуре, опираясь на корпоративную вики (Wiki.js). Цель — не фантазировать: если ответа в вики нет, агент честно говорит «нет данных».

## Уровень Light

### Топология

```
┌─────────────────────────────────────────────────────────────────────┐
│                  Домашняя локальная сеть 192.168.1.0/24             │
│                                                                     │
│   ┌─────────────────┐                                               │
│   │   Mac (клиент)  │                                               │
│   │  192.168.1.x    │  HTTP UI, ssh, git                            │
│   └────────┬────────┘                                               │
│            │                                                        │
│            │                                                        │
│   ┌────────┴────────────────────────────────────────────────┐       │
│   │  ПК хост   192.168.1.10                                 │       │
│   │  Ubuntu Server 24.04 + KVM/libvirt + Vagrant            │       │
│   │                                                          │      │
│   │  ┌──────────────┐  ┌──────────────┐                     │       │
│   │  │  aiwiki-pg   │  │ aiwiki-n8n   │                     │       │
│   │  │ 192.168.1.20 │  │ 192.168.1.21 │                     │       │
│   │  │ PostgreSQL16 │  │ Docker + n8n │                     │       │
│   │  │ :5432        │  │ :5678        │                     │       │
│   │  └──────┬───────┘  └──────┬───────┘                     │       │
│   │         │                  │                              │     │
│   │         │   ┌──────────────┴───────┐                     │       │
│   │         │   │                      │                     │       │
│   │  ┌──────┴───┴────┐  ┌──────────────┴┐                   │       │
│   │  │ aiwiki-wiki   │  │ aiwiki-ollama │                   │       │
│   │  │ 192.168.1.23  │  │ 192.168.1.22  │                   │       │
│   │  │ Docker+WikiJS │  │ Docker+Ollama │                   │       │
│   │  │ :3000         │  │ :11434        │                   │       │
│   │  └───────────────┘  └───────────────┘                   │       │
│   │                                                          │      │
│   └──────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

### Поток запроса

```
Сотрудник
   │
   │  открывает http://aiwiki-n8n.local:5678 (n8n chat trigger)
   ▼
n8n (aiwiki-n8n)
   │
   │  workflow:  Chat Trigger → AI Agent → Ollama Chat Model
   │  ┌─ память: Postgres Chat Memory → aiwiki-pg, db agent_memory
   │
   ├──► Ollama (aiwiki-ollama, http://192.168.1.22:11434)
   │       qwen2.5:3b-instruct
   │
   └──► Wiki.js (aiwiki-wiki) — на Light агент в Wiki.js не ходит,
        это появится на Normal через MCP-сервер
```

### PostgreSQL — три базы

| База | Пользователь | Кто пишет |
|------|--------------|-----------|
| `n8n` | `n8n_user` | n8n (workflow, executions, credentials) |
| `wikijs` | `wikijs_user` | Wiki.js (страницы, пользователи, права) |
| `agent_memory` | `agent_user` | n8n AI Agent (chat history) |

Доступ к 5432 — только из подсети `192.168.1.0/24` через `pg_hba.conf`.

### Что сохраняется при рестарте

- Данные `n8n` (workflow, credentials) — в БД `n8n` на `aiwiki-pg`
- Данные `Wiki.js` — в БД `wikijs` на `aiwiki-pg`
- Память агента — в БД `agent_memory` на `aiwiki-pg`
- Скачанные модели Ollama — в Docker volume на `aiwiki-ollama`

После `vagrant reload` любой ВМ (кроме `aiwiki-pg`) данные не теряются.

## Что появится дальше

- **Normal** — Redis + n8n worker, reverse-proxy nginx, MCP-сервер `avr-docs-mcp`, Ansible-роли
- **Hard** — всё переезжает в Kubernetes (Yandex Cloud), Prometheus/Grafana/Loki
- **Expert** — TLS на Ingress, бэкапы Postgres, GitOps

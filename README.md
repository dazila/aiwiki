# aiwiki

Учебный проект: внутренний AI-агент-ассистент, который отвечает на вопросы о корпоративной инфраструктуре, опираясь на корпоративную вики и не фантазируя.

## Стек

- **n8n** — оркестратор workflow и AI-агента
- **Ollama** — локальная LLM (стартовая модель: `qwen2.5:3b-instruct`)
- **Wiki.js** — корпоративная база знаний
- **PostgreSQL 16** — хранилище данных n8n, Wiki.js, и памяти агента
- **Redis** *(Normal+)* — очередь для n8n queue mode
- **MCP-сервер** *(Normal+)* — `avr-docs-mcp` для чтения Wiki.js агентом
- **Kubernetes / Terraform** *(Hard+)* — облачный кластер
- **Prometheus / Grafana / Loki** *(Hard+)* — мониторинг

## Уровни

Проект проходится последовательно по уровням сложности:

- **Light** — Vagrant + shell-provisioning, всё локально (текущий уровень)
- **Normal** — Ansible-роли, Redis + n8n queue mode, reverse-proxy, MCP
- **Hard** — Kubernetes в Yandex Cloud через Terraform, мониторинг
- **Expert** — GitOps, TLS, бэкапы, эксплуатационная документация

## Архитектура (Light)

```
ПК хост (Ubuntu Server 24.04 + KVM/libvirt + Vagrant)
192.168.1.10
│
├── aiwiki-pg       192.168.1.20   PostgreSQL 16, порт 5432
├── aiwiki-n8n      192.168.1.21   n8n в Docker, порт 5678
├── aiwiki-ollama   192.168.1.22   Ollama в Docker, порт 11434
└── aiwiki-wiki     192.168.1.23   Wiki.js в Docker, порт 3000
```

Все ВМ — в bridge-сети `br0` поверх физического Ethernet, IP резервируются на роутере по MAC. Имена резолвятся через mDNS (Avahi) — с любой машины в локалке доступны как `aiwiki-pg.local`, `aiwiki-n8n.local` и т.д.

PostgreSQL содержит три базы:

| База | Пользователь | Назначение |
|------|--------------|------------|
| `n8n` | `n8n_user` | данные n8n (workflow, креды, executions) |
| `wikijs` | `wikijs_user` | данные Wiki.js |
| `agent_memory` | `agent_user` | память AI-агента (chat history) |

## Структура репозитория

```
aiwiki/
├── README.md                  — этот файл
├── Vagrantfile                — описание ВМ
├── provisioning/              — shell-скрипты для bring-up
├── configs/                   — конфиги сервисов (compose, init.sql, env)
├── workflows/                 — экспорт workflow из n8n
└── docs/                      — архитектура, runbook, заметки
```

## Запуск

См. `docs/runbook-light.md` (появится по ходу этапов 0–8).

## Прогресс по Light

- [x] Этап 0 — подготовка хоста (Ubuntu Server, KVM, Vagrant, мост, Avahi)
- [ ] Этап 1 — Vagrantfile + 4 ВМ
- [ ] Этап 2 — PostgreSQL с тремя базами
- [ ] Этап 3 — n8n на Postgres
- [ ] Этап 4 — Ollama в ВМ + qwen2.5:3b-instruct
- [ ] Этап 5 — workflow Chat → AI Agent → Ollama
- [ ] Этап 6 — память агента в Postgres
- [ ] Этап 7 — Wiki.js + страница архитектуры
- [ ] Этап 8 — повторяемость + финальный smoke

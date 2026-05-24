### Hexlet tests and linter status

[![Actions Status](https://github.com/MamBoota/devops-for-developers-project-77/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/MamBoota/devops-for-developers-project-77/actions)

# DevOps for Developers — Project 77

IaC для приложения на **двух web-узлах** (Docker), **PostgreSQL**, **Nginx LB** в LAN (**HTTP**), публикация в интернет через **VPS** (HTTPS) и **reverse SSH**, оркестрация **Ansible** + **Terraform Cloud** (DNS-check, Datadog).

**Содержание:** [Команды](#основные-команды) · [Быстрый старт](#быстрый-старт) · [Архитектура](#архитектура) · [Мониторинг](#мониторинг) · [Структура репозитория](#структура-репозитория) · [Для проверяющего](#для-проверяющего)

---

## Основные команды

| Команда | Назначение |
|--------|------------|
| **`make start`** | Коллекции Ansible → плейбук `prepare,deploy,monitoring` → **`make relay-up`** (туннель на VPS, снаружи открывается домен). |
| **`make stop`** | **`make relay-stop`** → **`terraform destroy`** (в т.ч. Ansible destroy из Terraform). |
| **`make test`** | **Локально** (есть `.vault_pass`): ping VM, плейбук, HTTP по домену. **В GitHub Actions** / без `.vault_pass`: только `terraform validate` + `ansible-playbook --syntax-check` (секрет vault в репозиторий не кладётся). |
| **`make upmon-probe`** | Проверка URL и сигнал в [Upmon](https://app.upmon.com/) (нужен `scripts/upmon.local.env`, см. [docs/upmon.md](docs/upmon.md)). |
| **`make tf-apply`** | Синхронизация state, DNS-check, ресурсы Datadog (секреты в `terraform/secrets.auto.tfvars`). |

**Только туннель:** `make relay-up`, `make relay-stop`, `make relay-status`, `make relay-logs`. Переменные VPS/SSH — в начале `Makefile` (можно `make start VPS_USER=ubuntu`).

**Шаблоны:** `terraform/terraform.tfvars.example`, `terraform/secrets.auto.tfvars.example`.

---

## Быстрый старт

1. **Terraform Cloud:** workspace `StudentProj/project-77`, **Execution Mode = Local**.
2. **Локально:** файл `.vault_pass`, расшифровка vault в `ansible/group_vars/`.
3. **VPS:** Nginx + TLS, `proxy_pass http://127.0.0.1:18080;` — пример в [docs/vps-relay-nginx.conf.example](docs/vps-relay-nginx.conf.example).
4. **DNS:** A-запись домена → **публичный IP VPS**; тот же IP в `terraform.tfvars` как **`load_balancer_ip`** (не адрес `lb-1` в LAN).
5. Один раз с VPN: **`make tf-init`**, при необходимости **`make tf-apply`** и заполненный `secrets.auto.tfvars` для Datadog.
6. Рабочий цикл: **`make start`** → проверка `curl -I https://<домен>/` → по необходимости **`make test`**.

---

## Архитектура

- **LAN:** `web-1`, `web-2` — приложение `mamboota/devops-for-developers-project-74:latest`; `db-1` — PostgreSQL; `lb-1` — Nginx **без TLS**, прокси на приложения по HTTP (`:80`).
- **Интернет:** домен смотрит на **VPS**; на VPS TLS и прокси на `127.0.0.1:18080`; **SSH `-R`** с твоей машины пробрасывает этот порт на `lb-1:80` (как в **project-76**).
- **Terraform:** `load_balancer_ip` — IP **VPS** для проверки DNS; `application_url` в output — `https://<домен>/`.

---

## Мониторинг

**Datadog:** ключ агента в Ansible Vault (`vault_datadog_api_key`); агент ставится с `make start`. Монитор в Terraform — `secrets.auto.tfvars` + `make tf-apply`.

**Upmon (доступность снаружи):** Upmon ждёт **входящие** ping на выданный URL; зонд [scripts/upmon-probe.sh](scripts/upmon-probe.sh) сначала проверяет сайт, затем шлёт success/fail. Секрет — только в **`scripts/upmon.local.env`** (из `scripts/upmon.local.env.example`, файл в `.gitignore`). Подробно: [docs/upmon.md](docs/upmon.md).

---

## Структура репозитория

| Путь | Описание |
|------|----------|
| `terraform/` | Backend Terraform Cloud, `null_resource`, local-exec Ansible, Datadog |
| `ansible/` | Плейбуки, роли, `inventory.ini` |
| `docs/vps-relay-nginx.conf.example` | Пример vhost на VPS |
| `docs/upmon.md` | Настройка Upmon |
| `scripts/` | `upmon-probe.sh`, шаблон `upmon.local.env.example` |
| `Makefile` | Цели `start`, `stop`, `test`, relay, Terraform, Ansible |

---

## Требования

- Terraform ≥ 1.5, Ansible ≥ 2.14.
- Доступ к **Terraform Cloud** и **registry.terraform.io** (часто нужен **VPN**) для `make tf-init`, `make test`, `make tf-apply`, `make stop`.
- VM по `ansible/inventory.ini`, SSH-ключ в inventory.
- VPS с SSH с машины, где запускаешь `make relay-up`.

---

## Прочие цели Makefile

```text
make tf-init tf-validate tf-plan tf-apply tf-destroy tf-fmt
make ansible-deps ansible-prepare ansible-deploy ansible-monitoring
```

У `tf-init` — повторные попытки и кэш провайдеров в `~/.terraform.d/plugin-cache` (см. `Makefile`).

---

## Terraform Cloud

Если прервал `apply` / `destroy`, проверь незавершённые run в интерфейсе или CLI Terraform Cloud.

---

## Для проверяющего

- ТЗ: Terraform (`plan` / `apply` / `destroy`) + Ansible; основной плейбук `ansible/playbook.yml`.
- Публикация: домен → VPS, HTTPS на VPS, reverse SSH на локальный LB (HTTP); **не** прямой проброс 443 на Multipass-LB.
- **`load_balancer_ip`** в tfvars — публичный IP **VPS** для DNS-check.
- Мониторинг: Datadog (Ansible + Terraform) + Upmon по [docs/upmon.md](docs/upmon.md).
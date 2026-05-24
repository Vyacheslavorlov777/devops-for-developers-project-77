#!/usr/bin/env bash
# Проверяет доступность публичного URL приложения и шлёт сигнал в Upmon (success / fail).
# Upmon — «обратный» мониторинг: сервис ждёт HTTP-запросы на ваш ping-URL, а не ходит на сайт сам.
#
# Секрет (ping URL) храни в scripts/upmon.local.env (не коммитится) или в переменной окружения UPMON_PING_URL.
# Шаблон: scripts/upmon.local.env.example
#
# Пример crontab (каждые 5 минут), если используешь локальный env-файл:
#   */5 * * * * /path/to/repo/scripts/upmon-probe.sh >>/tmp/upmon-probe.log 2>&1
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_ENV="${SCRIPT_DIR}/upmon.local.env"
if [[ -f "$LOCAL_ENV" ]]; then
	set -a
	# shellcheck source=/dev/null
	source "$LOCAL_ENV"
	set +a
fi

SITE_URL="${1:-${UPMON_SITE_URL:-}}"
if [[ -z "$SITE_URL" ]]; then
	echo "Укажите URL страницы аргументом или задайте UPMON_SITE_URL в scripts/upmon.local.env" >&2
	echo "Пример: $0 https://myproj76.ru/" >&2
	exit 2
fi

UPMON_PING_URL="${UPMON_PING_URL:?Задайте UPMON_PING_URL в scripts/upmon.local.env (см. upmon.local.env.example) или в окружении}"

PING_OK="$UPMON_PING_URL"
PING_FAIL="${UPMON_PING_URL%/}/fail"

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }

if curl -fsS --max-time 30 -L -o /dev/null "$SITE_URL"; then
	log "OK: $SITE_URL — шлём success в Upmon"
	curl -fsS --max-time 30 -o /dev/null "$PING_OK"
else
	log "FAIL: $SITE_URL — шлём fail в Upmon"
	curl -fsS --max-time 30 -o /dev/null "$PING_FAIL" || true
	exit 1
fi

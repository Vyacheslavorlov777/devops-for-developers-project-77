# Доступность сервиса: Upmon

Задание курса: зарегистрироваться в **[Upmon](https://app.upmon.com/)** и добавить в мониторинг страницу проекта.

## Чем Upmon отличается от «классического» Pingdom

Upmon (как и близкий по идее [Healthchecks.io](https://healthchecks.io/)) в основном устроен как **dead man’s switch**: вы **сами** периодически делаете HTTP-запрос на **выданный сервисом ping-URL**. Пока запросы приходят вовремя — проверка «зелёная»; если перестали приходить — приходит алерт.

Сервис **не опрашивает ваш сайт из разных стран** автоматически. Чтобы связать это с **доступностью страницы**, нужен небольшой **зонд**: сначала запрос к вашему `https://…`, затем — success или fail в Upmon. Так вы получаете оповещение, если сайт не отвечает (или отвечает с ошибкой при проверке через `curl`).

Подробнее о настройке проверок: [Configuring Checks](https://app.upmon.com/docs/configuring_checks), про ping-URL: [Pinging API](https://app.upmon.com/docs/http_api).

## Шаги

1. Зарегистрируйся на **[app.upmon.com](https://app.upmon.com/)** и создай проект (при необходимости).
2. Создай **новую проверку (Check)** с понятным именем, например `project-77-https-home`.
3. Задай расписание (**Period** / **Grace Time**) с запасом под частоту запуска зонда. Например: период **5 minutes**, grace **2–3 minutes** (если зонд будет в cron раз в 5 минут).
4. Сохрани проверку и скопируй **success URL** вида `https://upmon.net/<uuid>` (или slug-URL из документации).
5. **Не коммить UUID в git.** Скопируй шаблон и положи секрет локально (файл в `.gitignore`):
   ```bash
   cp scripts/upmon.local.env.example scripts/upmon.local.env
   # отредактируй upmon.local.env: UPMON_PING_URL=... и при желании UPMON_SITE_URL=...
   ```
6. Убедись, что приложение доступно снаружи (`make start`, туннель, VPS).
7. Запусти зонд вручную из корня репозитория:
   ```bash
   make upmon-probe
   ```
   Либо `./scripts/upmon-probe.sh` / `./scripts/upmon-probe.sh "https://ВАШ-ДОМЕН/"`. Домен — в `upmon.local.env` как `UPMON_SITE_URL` или аргументом; URL из `terraform output application_url` / `redmine_domain`.

   В репозитории **нет** файла `upmon.local.env` — только шаблон `.example`, чтобы секреты никогда не уезжали в git.
8. Поставь зонд на расписание, например **cron** (секреты только в `upmon.local.env` на той машине, где крутится cron):
   ```cron
   */5 * * * * cd /полный/путь/devops-for-developers-project-77 && ./scripts/upmon-probe.sh >>/tmp/upmon-probe.log 2>&1
   ```
9. Включи **уведомления** (email/Telegram и т.д.) в Upmon: [Configuring notifications](https://app.upmon.com/docs/configuring_notifications).

## Идеи по усложнению

- Разные точки зрения: cron на VPS в одном регионе + отдельный запуск (другой хост / GitHub Actions) — два независимых сценария проверки.
- Следить за временем ответа: в `scripts/upmon-probe.sh` можно добавить разбор `curl -w '%{time_total}'` и при превышении порога вызывать `${UPMON_PING_URL}/fail`.

## Секреты

Файл **`scripts/upmon.local.env`** перечислен в **`.gitignore`** и не должен попадать в коммиты. В репозитории только **`scripts/upmon.local.env.example`** без настоящего UUID.

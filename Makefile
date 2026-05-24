# POSIX sh: в Docker/Alpine часто нет bash; [[ и {1..n} там не работают.
SHELL := /bin/sh

TF_DIR=terraform
ANSIBLE_DIR=ansible
ANSIBLE_COLLECTIONS_DIR=.ansible/collections
# Кэш бинарников провайдеров (make tf-init с VPN).
TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache

# Публичный доступ как в project-76: reverse SSH tunnel на VPS + HTTPS на VPS.
DOMAIN ?= myproj76.ru
VPS_IP ?= 168.222.143.207
VPS_USER ?= root
SSH_KEY ?= $(HOME)/.ssh/multipass_ansible
# Отдельный ключ для VPS (по умолчанию тот же, что для VM).
VPS_SSH_KEY ?= $(SSH_KEY)
RELAY_REMOTE_PORT ?= 18080
RELAY_PID_FILE ?= /tmp/vps-relay-project77.pid
RELAY_LOG ?= /tmp/vps-relay-project77.log
LB_ORIGIN ?= 192.168.2.5:80
SSH_USER ?= ubuntu
APP1_IP ?= 192.168.2.2
APP2_IP ?= 192.168.2.3
LB_IP ?= 192.168.2.5

.PHONY: start stop test check ci setup lint upmon-probe relay-up relay-stop relay-status relay-logs tf-init tf-fmt tf-validate tf-plan tf-apply tf-destroy ansible-deps ansible-prepare ansible-deploy ansible-monitoring

# Hexlet: docker compose run app make setup.
# В CI/Docker пропускаем ansible-galaxy (зависит от внешней сети), оставляем terraform init.
setup: tf-init
	@if [ -z "$$GITHUB_ACTIONS" ] && [ -z "$$CI" ] && [ ! -f /.dockerenv ]; then \
		$(MAKE) ansible-deps; \
	fi
	@echo "OK: setup"

# Образ Hexlet кладёт ansible-lint.yml в корень проекта, код — в подкаталог: ищем конфиг в . и ..
lint:
	@cfg=""; for d in . ..; do test -f "$$d/ansible-lint.yml" && cfg="$$d/ansible-lint.yml" && break; done; \
	if [ -n "$$cfg" ]; then ansible-lint -c "$$cfg" $(ANSIBLE_DIR)/; else ansible-lint $(ANSIBLE_DIR)/; fi

# Некоторые сценарии CI вызывают make check вместо make test.
check: test

ci: lint test

# Один шаг: Ansible (prepare+deploy+monitoring) + reverse SSH на VPS (публичный URL).
start: ansible-deps
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-playbook -i $(ANSIBLE_DIR)/inventory.ini $(ANSIBLE_DIR)/playbook.yml --tags prepare,deploy,monitoring --vault-password-file .vault_pass
	@$(MAKE) relay-up

# Один шаг: гасим туннель, затем terraform destroy (как в ТЗ курса).
stop: relay-stop
	$(MAKE) tf-destroy

# Проверка сайта + сигнал в Upmon (нужен scripts/upmon.local.env из .example, не коммитится).
upmon-probe:
	@test -f scripts/upmon.local.env || (echo "Создай scripts/upmon.local.env: cp scripts/upmon.local.env.example scripts/upmon.local.env и задай UPMON_PING_URL"; exit 1)
	@./scripts/upmon-probe.sh

# Проверки: terraform validate; локально с .vault_pass — ping VM, self-heal, HTTP.
# В CI/без vault: только Terraform-валидация (ansible-lint запускается отдельной целью lint).
test: tf-validate
	@if [ -n "$$GITHUB_ACTIONS" ] || [ -n "$$CI" ] || [ ! -f .vault_pass ]; then \
		echo "=== CI или нет .vault_pass: только terraform validate ==="; \
		echo "OK: статическая проверка Terraform. Локально с .vault_pass выполни make test для полного прогона."; \
	else \
		$(MAKE) ansible-deps; \
		ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible -i $(ANSIBLE_DIR)/inventory.ini all -m ping --vault-password-file .vault_pass; \
		ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-playbook -i $(ANSIBLE_DIR)/inventory.ini $(ANSIBLE_DIR)/playbook.yml --syntax-check --vault-password-file .vault_pass; \
		ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-playbook -i $(ANSIBLE_DIR)/inventory.ini $(ANSIBLE_DIR)/playbook.yml --tags prepare,deploy,monitoring --vault-password-file .vault_pass >/tmp/make-test-self-heal.log 2>&1 || (echo "Self-heal failed. Last lines:"; tail -n 40 /tmp/make-test-self-heal.log; exit 1); \
		url="$$(terraform -chdir=$(TF_DIR) output -raw application_url 2>/dev/null || true)"; \
		if [ -z "$$url" ] && [ -f "$(TF_DIR)/terraform.tfvars" ]; then \
			domain=$$(awk -F'"' '/redmine_domain/{print $$2; exit}' "$(TF_DIR)/terraform.tfvars"); \
			if [ -n "$$domain" ]; then url="https://$$domain"; fi; \
		fi; \
		if [ -z "$$url" ]; then url="https://$(DOMAIN)"; fi; \
		url="$${url%/}"; \
		echo "Testing $$url (TLS на VPS; локальный lb-1 — HTTP, см. README и make relay-up) ..."; \
		ready=0; \
		i=1; while [ "$$i" -le 15 ]; do \
			code=$$(curl --max-time 8 -s -o /dev/null -w '%{http_code}' "$$url"); \
			echo "warmup $$i:$$code"; \
			if [ "$$code" = "200" ] || [ "$$code" = "301" ] || [ "$$code" = "302" ]; then ready=1; break; fi; \
			sleep 1; \
			i=$$((i + 1)); \
		done; \
		if [ "$$ready" -ne 1 ]; then \
			echo "FAIL: нет HTTP 200/301/302 за warm-up. Выполни make start (деплой+tunnel), проверь Nginx на VPS → 127.0.0.1:$(RELAY_REMOTE_PORT). См. docs/vps-relay-nginx.conf.example"; \
			exit 1; \
		fi; \
		ok=1; \
		i=1; while [ "$$i" -le 10 ]; do \
			code=$$(curl --max-time 8 -s -o /dev/null -w '%{http_code}' "$$url"); \
			echo "$$i:$$code"; \
			if [ "$$code" != "200" ] && [ "$$code" != "301" ] && [ "$$code" != "302" ]; then ok=0; fi; \
			sleep 1; \
			i=$$((i + 1)); \
		done; \
		if [ "$$ok" -eq 1 ]; then \
			echo "PASS: 10/10 ответов в ожидаемых кодах (200/301/302)"; \
		else \
			echo "FAIL: встречен неожиданный HTTP-код"; \
			exit 1; \
		fi; \
	fi

relay-up:
	@echo "Подготовка Docker на app-узлах и reload nginx на LB ..."
	@for host in $(APP1_IP) $(APP2_IP); do \
		echo "Docker на $$host ..."; \
		ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no $(SSH_USER)@$$host \
			"sudo systemctl start docker.socket 2>/dev/null || true; sudo systemctl start docker 2>/dev/null || true"; \
	done
	@echo "Reload nginx на $(LB_IP) ..."
	@ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no $(SSH_USER)@$(LB_IP) \
		"sudo systemctl reload nginx 2>/dev/null || sudo systemctl restart nginx"
	@echo "Ожидание HTTP 200 с lb-1 (локально) ..."
	@ok=0; \
	i=1; while [ "$$i" -le 15 ]; do \
		code=$$(ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no $(SSH_USER)@$(LB_IP) \
			"curl --max-time 5 -s -o /dev/null -w '%{http_code}' http://127.0.0.1/"); \
		echo "$$i:$$code"; \
		if [ "$$code" = "200" ] || [ "$$code" = "301" ] || [ "$$code" = "302" ]; then ok=1; break; fi; \
		sleep 1; \
		i=$$((i + 1)); \
	done; \
	if [ "$$ok" -ne 1 ]; then \
		echo "Локальный LB не отвечает 200/301/302. Выполни make start."; \
		exit 1; \
	fi
	@echo "Запуск reverse SSH: $(VPS_USER)@$(VPS_IP) <- $(LB_ORIGIN) (remote 127.0.0.1:$(RELAY_REMOTE_PORT)) ..."
	@if [ -f "$(RELAY_PID_FILE)" ]; then kill $$(cat "$(RELAY_PID_FILE)") 2>/dev/null || true; rm -f "$(RELAY_PID_FILE)"; fi
	@pkill -f "$(RELAY_REMOTE_PORT):$(LB_ORIGIN)" 2>/dev/null || true
	@sleep 1
	@nohup ssh -i "$(VPS_SSH_KEY)" \
		-o ExitOnForwardFailure=yes \
		-o ServerAliveInterval=30 \
		-o ServerAliveCountMax=3 \
		-o StrictHostKeyChecking=no \
		-N -R 127.0.0.1:$(RELAY_REMOTE_PORT):$(LB_ORIGIN) \
		$(VPS_USER)@$(VPS_IP) >"$(RELAY_LOG)" 2>&1 & echo $$! > "$(RELAY_PID_FILE)"
	@sleep 2
	@kill -0 $$(cat "$(RELAY_PID_FILE)") 2>/dev/null && \
		echo "Relay запущен (PID $$(cat $(RELAY_PID_FILE)), лог: $(RELAY_LOG))." || \
		(echo "Relay не стартовал. См. $(RELAY_LOG)"; exit 1)

relay-stop:
	@echo "Остановка reverse relay к $(VPS_USER)@$(VPS_IP) ..."
	@if [ -f "$(RELAY_PID_FILE)" ]; then kill $$(cat "$(RELAY_PID_FILE)") 2>/dev/null || true; rm -f "$(RELAY_PID_FILE)"; fi
	@pkill -f "$(RELAY_REMOTE_PORT):$(LB_ORIGIN)" 2>/dev/null || true
	@sleep 1
	@if pgrep -f "$(RELAY_REMOTE_PORT):$(LB_ORIGIN)" >/dev/null 2>&1; then \
		echo "Предупреждение: похожий ssh-процесс ещё есть — при необходимости убей вручную (ps aux | grep ssh)."; \
	else \
		echo "Relay остановлен."; \
	fi

relay-status:
	@echo "PID-файл relay:"
	@if [ -f "$(RELAY_PID_FILE)" ]; then \
		echo "  $$(cat $(RELAY_PID_FILE)) (жив: $$(kill -0 $$(cat $(RELAY_PID_FILE)) 2>/dev/null && echo да || echo нет))"; \
	else echo "  нет"; fi
	@echo "Проверка домена (HTTPS на VPS):"
	@curl --max-time 8 -s -o /dev/null -w "https://$(DOMAIN) -> %{http_code}\n" "https://$(DOMAIN)" || true

relay-logs:
	@echo "Хвост $(RELAY_LOG):"
	@tail -n 40 "$(RELAY_LOG)" 2>/dev/null || echo "нет файла"

# В GitHub Actions и в Docker (Hexlet: docker build RUN make …) нет Terraform Cloud token.
# Там init сразу с -backend=false; локально вне контейнера — обычный remote backend + fallback ниже.
tf-init:
	@mkdir -p "$(TF_PLUGIN_CACHE_DIR)"; \
	INIT_EXTRA=""; \
	if [ -n "$$GITHUB_ACTIONS" ] || [ -n "$$CI" ]; then \
		INIT_EXTRA="-backend=false"; \
		echo "terraform init: CI — только провайдеры (-backend=false), без Terraform Cloud"; \
	elif [ -f /.dockerenv ]; then \
		INIT_EXTRA="-backend=false"; \
		echo "terraform init: Docker — только провайдеры (-backend=false), без Terraform Cloud"; \
	fi; \
	n=0; \
	until [ $$n -ge 3 ]; do \
		if TF_PLUGIN_CACHE_DIR="$(TF_PLUGIN_CACHE_DIR)" terraform -chdir=$(TF_DIR) init -input=false $$INIT_EXTRA; then \
			exit 0; \
		fi; \
		n=$$((n+1)); \
		if [ $$n -lt 3 ]; then echo "terraform init failed, retry $$n/3 in 5s..."; sleep 5; fi; \
	done; \
	if [ -z "$$INIT_EXTRA" ]; then \
		echo "terraform init: нет доступа к remote backend — пробуем -backend=false (validate / образ Hexlet без TFC)..."; \
		if TF_PLUGIN_CACHE_DIR="$(TF_PLUGIN_CACHE_DIR)" terraform -chdir=$(TF_DIR) init -input=false -backend=false; then \
			exit 0; \
		fi; \
	fi; \
	echo "terraform init failed after 3 attempts (VPN / registry.terraform.io / для локали — Terraform Cloud)"; \
	exit 1

tf-fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

tf-validate: tf-init
	terraform -chdir=$(TF_DIR) validate

tf-plan:
	terraform -chdir=$(TF_DIR) plan

tf-apply:
	terraform -chdir=$(TF_DIR) apply -auto-approve

tf-destroy:
	terraform -chdir=$(TF_DIR) destroy -auto-approve

ansible-deps:
	mkdir -p $(ANSIBLE_COLLECTIONS_DIR)
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-galaxy collection install -r $(ANSIBLE_DIR)/requirements.yml -p $(ANSIBLE_COLLECTIONS_DIR)

ansible-prepare:
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-playbook -i $(ANSIBLE_DIR)/inventory.ini $(ANSIBLE_DIR)/playbook.yml --tags prepare --vault-password-file .vault_pass

ansible-deploy:
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-playbook -i $(ANSIBLE_DIR)/inventory.ini $(ANSIBLE_DIR)/playbook.yml --tags prepare,deploy,monitoring --vault-password-file .vault_pass

ansible-monitoring:
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_DIR) ansible-playbook -i $(ANSIBLE_DIR)/inventory.ini $(ANSIBLE_DIR)/playbook.yml --tags monitoring --vault-password-file .vault_pass

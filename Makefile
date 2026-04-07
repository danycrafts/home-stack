# =============================================================================
# LOCAL INFRASTRUCTURE - MAKEFILE
# =============================================================================

# Load environment variables
ifneq ($(wildcard .env),)
  include .env
  export
else
  $(warning .env not found — run: cp .env.example .env)
endif

COMPOSE_FLAGS := -f docker-compose.yml
DOMAIN := $(DOMAIN_NAME)
BLUE  := \033[34m
GREEN := \033[32m
YELLOW:= \033[33m
RED   := \033[31m
NC    := \033[0m

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "$(BLUE)Local Infrastructure$(NC)"
	@echo ""
	@echo "Domain: $(GREEN)${DOMAIN}$(NC)"
	@echo ""
	@echo "$(GREEN)Setup:$(NC)"
	@echo "  make init              Create volume directories"
	@echo "  make up                Start all services"
	@echo ""
	@echo "$(GREEN)Management:$(NC)"
	@echo "  make down              Stop services"
	@echo "  make restart           Restart services"
	@echo "  make logs              Tail logs"
	@echo "  make logs SERVICE=n8n  Tail specific service logs"
	@echo "  make pull              Pull latest images"
	@echo "  make ps                Show service status"
	@echo "  make status            Show running containers"
	@echo "  make health            Show health status"
	@echo ""
	@echo "$(GREEN)Service URLs:$(NC)"
	@echo "  PgAdmin:        http://pgadmin.${DOMAIN} (or http://localhost:5050)"
	@echo "  Keycloak:       http://keycloak.${DOMAIN} (or http://localhost:8080)"
	@echo "  n8n:            http://n8n.${DOMAIN} (or http://localhost:5678)"
	@echo "  NPM Admin:      http://npm.${DOMAIN} (or http://localhost:81)"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make clean             Remove stopped containers"
	@echo "  make prune             DANGER: remove all data including volumes"
	@echo "  make setup-proxy       Configure NPM proxy hosts"

# =============================================================================
# SETUP
# =============================================================================

.PHONY: init
init: _check-env _create-volumes
	@echo "$(GREEN)✓ Local infrastructure ready$(NC)"

.PHONY: _check-env
_check-env:
	@test -f .env || (echo "$(RED)ERROR: cp .env.example .env$(NC)" && exit 1)

.PHONY: _create-volumes
_create-volumes:
	@echo "$(BLUE)Creating volume directories...$(NC)"
	@chmod +x services/postgres/init/*.sh 2>/dev/null || true
	@chmod +x services/nginx-proxy-manager/*.sh 2>/dev/null || true
	@echo "  ✓ Volume directories ready"

# =============================================================================
# MAIN COMMANDS
# =============================================================================

.PHONY: up
up: init
	@echo "$(BLUE)Starting local infrastructure...$(NC)"
	@docker compose $(COMPOSE_FLAGS) up -d
	@echo "$(GREEN)✓ Services started$(NC)"
	@echo ""
	@echo "$(GREEN)Access URLs:$(NC)"
	@echo "  PgAdmin:    http://pgadmin.${DOMAIN} (or http://localhost:5050)"
	@echo "  Keycloak:   http://keycloak.${DOMAIN} (or http://localhost:8080)"
	@echo "  n8n:        http://n8n.${DOMAIN} (or http://localhost:5678)"
	@echo "  NPM Admin:  http://npm.${DOMAIN} (or http://localhost:81)"
	@echo ""
	@echo "$(YELLOW)Run 'make setup-proxy' to configure proxy hosts$(NC)"

.PHONY: down
down:
	@echo "$(YELLOW)Stopping services...$(NC)"
	@docker compose $(COMPOSE_FLAGS) down

.PHONY: restart
restart: down up

SERVICE ?=

.PHONY: logs
logs:
ifdef SERVICE
	@docker compose $(COMPOSE_FLAGS) logs -f $(SERVICE)
else
	@docker compose $(COMPOSE_FLAGS) logs -f --tail=100
endif

.PHONY: pull
pull:
	@docker compose $(COMPOSE_FLAGS) pull

.PHONY: ps
ps:
	@docker compose $(COMPOSE_FLAGS) ps

.PHONY: status
status:
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|local-)" || echo "No containers running"

.PHONY: health
health:
	@echo "$(BLUE)Health Status:$(NC)"
	@for name in local-postgres local-pgadmin local-keycloak local-n8n local-npm; do \
		id=$$(docker ps -qf "name=$${name}" 2>/dev/null); \
		if [ -n "$$id" ]; then \
			status=$$(docker inspect --format '{{.State.Status}}' "$$id" 2>/dev/null); \
			health=$$(docker inspect --format '{{.State.Health.Status}}' "$$id" 2>/dev/null || echo "no healthcheck"); \
			printf "  %-20s %-12s %s\n" "$$name" "$$status" "$$health"; \
		fi; \
	done

# =============================================================================
# PROXY SETUP
# =============================================================================

.PHONY: setup-proxy
setup-proxy:
	@echo "$(BLUE)Configuring Nginx Proxy Manager...$(NC)"
	@docker exec local-npm bash -c '\
		NPM_URL="http://localhost:81"; \
		DOMAIN="$(DOMAIN_NAME)"; \
		ADMIN_EMAIL="$(ADMIN_EMAIL)"; \
		ADMIN_PASSWORD="$(ADMIN_PASSWORD)"; \
		PGADMIN_SUBDOMAIN="$(PGADMIN_SUBDOMAIN)"; \
		KC_SUBDOMAIN="$(KC_SUBDOMAIN)"; \
		N8N_SUBDOMAIN="$(N8N_SUBDOMAIN)"; \
		NPM_ADMIN_SUBDOMAIN="$(NPM_ADMIN_SUBDOMAIN)"; \
		source /tmp/init-proxy-hosts.sh' 2>/dev/null || \
	docker cp services/nginx-proxy-manager/init-proxy-hosts.sh local-npm:/tmp/ && \
	docker exec -e DOMAIN_NAME=$(DOMAIN_NAME) \
		-e ADMIN_EMAIL=$(ADMIN_EMAIL) \
		-e ADMIN_PASSWORD=$(ADMIN_PASSWORD) \
		-e PGADMIN_SUBDOMAIN=$(PGADMIN_SUBDOMAIN) \
		-e KC_SUBDOMAIN=$(KC_SUBDOMAIN) \
		-e N8N_SUBDOMAIN=$(N8N_SUBDOMAIN) \
		-e NPM_ADMIN_SUBDOMAIN=$(NPM_ADMIN_SUBDOMAIN) \
		local-npm bash /tmp/init-proxy-hosts.sh || \
	echo "$(YELLOW)Proxy setup may need to be done manually$(NC)"

# =============================================================================
# UTILITIES
# =============================================================================

.PHONY: clean
clean:
	@echo "$(YELLOW)Cleaning up...$(NC)"
	@docker system prune -f
	@echo "$(GREEN)✓ Done$(NC)"

.PHONY: prune
prune:
	@echo "$(RED)WARNING: This will delete ALL data including volumes!$(NC)"
	@read -rp "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@docker compose $(COMPOSE_FLAGS) down -v --remove-orphans
	@docker system prune -af --volumes
	@echo "$(GREEN)✓ Everything removed$(NC)"

.PHONY: validate
validate:
	@echo "$(BLUE)Validating docker-compose.yml...$(NC)"
	@docker compose $(COMPOSE_FLAGS) config > /dev/null && echo "$(GREEN)✓ Valid$(NC)" || echo "$(RED)✗ Invalid$(NC)"

.PHONY: shell-postgres
shell-postgres:
	@docker exec -it local-postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}

.PHONY: shell-n8n
shell-n8n:
	@docker exec -it local-n8n /bin/sh

.PHONY: shell-keycloak
shell-keycloak:
	@docker exec -it local-keycloak /bin/bash

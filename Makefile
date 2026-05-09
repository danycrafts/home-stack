# Home Stack

.PHONY: help up down restart certs logs status reset test clean config

help:
	@echo "Home Stack - Available Commands:"
	@echo ""
	@echo "  make up       - Build and start the clean stack"
	@echo "  make certs    - Issue/refresh Let's Encrypt certificates"
	@echo "  make down     - Stop services"
	@echo "  make restart  - Recreate services"
	@echo "  make reset    - Stop services and remove volumes"
	@echo "  make config   - Validate compose config"
	@echo "  make test     - Run local health checks"
	@echo "  make logs     - Follow logs"
	@echo "  make status   - Show service status"
	@echo "  make clean    - Remove unused Docker resources"
	@echo ""

up:
	docker compose up -d --build --force-recreate

certs:
	docker compose exec nginx /usr/local/bin/certbot-issue

down:
	docker compose down --remove-orphans

restart:
	docker compose down --remove-orphans
	docker compose up -d --build --force-recreate

reset:
	docker compose down -v --remove-orphans

logs:
	docker compose logs -f

status:
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

config:
	docker compose config --quiet

test:
	docker compose config --quiet
	curl -fsS http://localhost/healthz >/dev/null
	curl -kfsS https://nginx.invariantcontinuum.io/healthz --resolve nginx.invariantcontinuum.io:443:127.0.0.1 >/dev/null
	curl -kfsS https://pgadmin.invariantcontinuum.io/healthz --resolve pgadmin.invariantcontinuum.io:443:127.0.0.1 >/dev/null
	curl -kfsS https://auth.invariantcontinuum.io/healthz --resolve auth.invariantcontinuum.io:443:127.0.0.1 >/dev/null
	curl -kfsS https://redis.invariantcontinuum.io/healthz --resolve redis.invariantcontinuum.io:443:127.0.0.1 >/dev/null
	docker compose exec -T postgres pg_isready -U postgres -d postgres
	docker compose exec -T redis redis-cli -a "$${REDIS_PASSWORD:-changeme}" ping

clean:
	docker system prune -f

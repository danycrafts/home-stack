# =============================================================================
# Local Infrastructure Stack - Makefile
# =============================================================================

.PHONY: help up down provision logs status reset test clean

# Default target
help:
	@echo "Local Infrastructure Stack - Available Commands:"
	@echo ""
	@echo "  make up         - Start all services"
	@echo "  make provision  - Run IaC provisioning (creates proxy hosts)"
	@echo "  make deploy     - Start services and run provisioning"
	@echo "  make down       - Stop all services"
	@echo "  make reset      - Stop and remove all data (WARNING: destructive!)"
	@echo "  make logs       - View logs from all services"
	@echo "  make status     - Check service status"
	@echo "  make test       - Test all services are accessible"
	@echo "  make clean      - Remove unused Docker resources"
	@echo ""

# Start all core services
up:
	@echo "🚀 Starting infrastructure services..."
	docker compose up -d postgres nginx-proxy-manager
	@echo "⏳ Waiting for core services to be healthy..."
	@sleep 10
	docker compose up -d pgadmin keycloak n8n
	@echo "✓ Services starting..."

# Run IaC provisioning (creates proxy hosts in NPM)
provision:
	@echo "🔧 Running IaC provisioning..."
	docker compose --profile provision up -d npm-provisioner
	@sleep 5
	@echo ""
	@echo "📋 Provisioner logs:"
	docker compose --profile provision logs npm-provisioner

# Full deploy: start services and provision
deploy: up
	@echo ""
	@echo "⏳ Waiting for services to stabilize..."
	@sleep 30
	@$(MAKE) provision
	@echo ""
	@echo "✅ Deployment complete!"
	@$(MAKE) status

# Stop all services
down:
	@echo "🛑 Stopping all services..."
	docker compose --profile provision down

# Stop and remove all data (DESTRUCTIVE!)
reset:
	@echo "⚠️  WARNING: This will delete ALL data!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "🗑️  Removing all services and data..."
	docker compose --profile provision down -v
	@echo "✓ All data removed"

# View logs
logs:
	docker compose logs -f

# Check service status
status:
	@echo "============================================================================="
	@echo "  Service Status"
	@echo "============================================================================="
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Test all services
test:
	@echo "============================================================================="
	@echo "  Testing Services"
	@echo "============================================================================="
	@echo ""
	@echo -n "PostgreSQL (localhost:5432)... "
	@nc -z localhost 5432 && echo "✓ OK" || echo "✗ FAILED"
	@echo -n "PgAdmin (localhost:5050)... "
	@curl -sf http://localhost:5050 >/dev/null && echo "✓ OK" || echo "✗ FAILED"
	@echo -n "Keycloak (localhost:8080)... "
	@curl -sf http://localhost:8080/admin >/dev/null && echo "✓ OK" || echo "✗ FAILED"
	@echo -n "n8n (localhost:5678)... "
	@curl -sf http://localhost:5678/healthz >/dev/null && echo "✓ OK" || echo "✗ FAILED"
	@echo -n "NPM (localhost:81)... "
	@curl -sf http://localhost:81/api/ >/dev/null && echo "✓ OK" || echo "✗ FAILED"
	@echo ""

# Clean up unused Docker resources
clean:
	@echo "🧹 Cleaning up unused Docker resources..."
	docker system prune -f
	@echo "✓ Cleanup complete"

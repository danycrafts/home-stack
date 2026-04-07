# Home Stack - Agent Instructions

## Overview

This is the Home Stack infrastructure - a modular Docker Compose setup providing core infrastructure, applications, and data services for the `invariantcontinuum.io` domain.

**Stack Components:**
- **Core:** PostgreSQL 16, Redis 7 (with Redis Commander), NATS 3-node cluster
- **Apps:** Keycloak (IAM), n8n (workflows), PgAdmin, Nginx Proxy Manager
- **Data:** MinIO, Qdrant, Neo4j, Elasticsearch

---

## Directory Structure

```
home-stack/
├── docker-compose.yml          # Main orchestrator with includes
├── .env                        # Environment variables (NOT in git)
├── .env.example                # Template for .env
├── home-stack-local.md         # LOCAL ONLY - credentials & links
├── core/                       # Core infrastructure services
│   ├── postgres.yml
│   ├── redis.yml              # + Redis Commander
│   └── nats.yml               # 3-node JetStream cluster
├── apps/                       # Application services
│   ├── nginx-proxy-manager.yml
│   ├── keycloak.yml           # OAuth/OpenID provider
│   ├── n8n.yml                # Workflow automation
│   └── pgadmin.yml            # PostgreSQL management
├── data/                       # Data storage services
│   ├── minio.yml              # S3-compatible storage
│   ├── qdrant.yml             # Vector database
│   ├── neo4j.yml              # Graph database
│   └── elasticsearch.yml      # Search engine
└── services/                   # Service-specific configs
    ├── postgres/init/
    ├── keycloak/
    ├── pgadmin/
    └── nginx-proxy-manager/
```

---

## Critical Rules

### 1. ALWAYS Update home-stack-local.md

**Whenever you make ANY changes to the stack, you MUST update `home-stack-local.md`:**

- Add/remove services
- Change credentials or environment variables
- Modify ports or URLs
- Update configuration details
- Add new proxy hosts

The `home-stack-local.md` file is the source of truth for local service documentation and credentials. It stays on the device (git-ignored) and contains plain-text passwords.

**What to update in home-stack-local.md:**
- Service URLs and ports
- Connection strings
- Credentials (username/password)
- Database names and users
- OAuth client secrets
- API endpoints
- Environment variable changes
- Troubleshooting notes for new services

### 2. Verify Changes Before Committing

**ALL changes to the home-stack MUST be verified:**

```bash
# 1. Navigate to the stack directory
cd ~/github/danycrafts/home-stack

# 2. Recreate the target service to verify it starts cleanly
docker compose -f <path/to/service.yml> up -d --force-recreate <service-name>

# Example:
docker compose -f core/redis.yml up -d --force-recreate redis

# 3. Check logs for errors, issues, or warnings
docker logs -f local-<service-name>

# 4. Verify no errors in output:
# - Look for ERROR, FATAL, CRITICAL messages
# - Check for connection failures
# - Verify health checks pass
# - Ensure no deprecation warnings that affect functionality
```

**Verification Checklist:**
- [ ] Container starts successfully
- [ ] No ERROR or FATAL logs
- [ ] Health check passes (if configured)
- [ ] Service is accessible on expected port
- [ ] No connection issues to dependent services
- [ ] Configuration is correctly loaded

### 3. Environment Variable Synchronization

When adding/modifying environment variables:

1. Update `.env` with the actual values
2. Update `.env.example` with placeholder values (no secrets)
3. Update `home-stack-local.md` with the variable names and values
4. Verify the service reads the variables correctly

### 4. Service Dependencies

Services have dependencies - respect the startup order:

```
postgres (core) → keycloak, n8n, pgadmin
keycloak (apps) → n8n, pgadmin
redis (core) → redis-commander
nats-* (core) → no dependents
```

When modifying dependent services, always verify the dependency chain still works.

### 5. Proxy Host Provisioning

Nginx Proxy Manager proxy hosts are provisioned via IaC in `init-proxy-hosts.sh`.

When adding a new public-facing service:

1. Add subdomain variable to `.env` and `.env.example`
2. Add `create_proxy_host_https` call in `services/nginx-proxy-manager/init-proxy-hosts.sh`
3. Update `home-stack-local.md` with the HTTPS URL
4. Re-run provisioner to test: `docker compose -f apps/nginx-proxy-manager.yml run --rm npm-provisioner`

### 6. Git Workflow

**Commit Message Format:**
```bash
# Format: <type>(<scope>): <description>
git commit -m "feat(core): add redis-commander for redis management"
git commit -m "fix(apps): update keycloak realm configuration"
git commit -m "docs: update home-stack-local.md with new credentials"
```

**Never commit:**
- `.env` file (contains secrets)
- `home-stack-local.md` (contains plain-text passwords)

**Always commit:**
- `.env.example` (template without secrets)
- All `.yml` compose files
- All configuration files in `services/`
- `AGENTS.md` (this file)

---

## Common Tasks

### Add a New Service

1. Create compose file in appropriate folder (`core/`, `apps/`, or `data/`)
2. Add include to root `docker-compose.yml`
3. Add volume definition if needed
4. Add environment variables to `.env` and `.env.example`
5. Add proxy host to `init-proxy-hosts.sh` (if public)
6. **Verify service starts cleanly** (see rule #2)
7. **Update `home-stack-local.md`** with service details
8. Commit changes

### Update Service Configuration

1. Modify the compose file
2. **Recreate the service** and verify no errors
3. **Update `home-stack-local.md`** if URLs/ports/credentials changed
4. Commit changes

### Update Credentials

1. Change in `.env`
2. **Update `home-stack-local.md`** with new credentials
3. Recreate affected services to apply changes
4. Verify services reconnect properly

---

## Service Quick Reference

| Service | Compose File | Container Name | Health Check |
|---------|-------------|----------------|--------------|
| PostgreSQL | `core/postgres.yml` | `local-postgres` | `pg_isready` |
| Redis | `core/redis.yml` | `local-redis` | `redis-cli ping` |
| Redis Commander | `core/redis.yml` | `local-redis-commander` | None |
| NATS-1 | `core/nats.yml` | `local-nats-1` | HTTP 8222 |
| NATS-2 | `core/nats.yml` | `local-nats-2` | HTTP 8222 |
| NATS-3 | `core/nats.yml` | `local-nats-3` | HTTP 8222 |
| Keycloak | `apps/keycloak.yml` | `local-keycloak` | HTTP 8080 |
| n8n | `apps/n8n.yml` | `local-n8n` | None |
| PgAdmin | `apps/pgadmin.yml` | `local-pgadmin` | None |
| NPM | `apps/nginx-proxy-manager.yml` | `local-npm` | HTTP 81 |
| MinIO | `data/minio.yml` | `local-minio` | HTTP 9000 |
| Qdrant | `data/qdrant.yml` | `local-qdrant` | HTTP 6333 |
| Neo4j | `data/neo4j.yml` | `local-neo4j` | HTTP 7474 |
| Elasticsearch | `data/elasticsearch.yml` | `local-elasticsearch` | HTTP 9200 |

---

## Network & Storage

**Network:** `local-infra-network` (bridge)

**All volumes prefixed with `local-`:**
- `local-postgres-data`
- `local-redis-data`
- `local-n8n-data`
- `local-npm-data`
- `local-minio-data`
- `local-qdrant-data`
- `local-neo4j-data`
- `local-es-data`
- `local-nats-data`, `local-nats-data-2`, `local-nats-data-3`

---

## Troubleshooting

**Service won't start:**
```bash
# Check logs
docker logs local-<service-name>

# Check if dependencies are healthy
docker compose -f core/postgres.yml ps

# Recreate with clean state
docker compose -f <compose-file> up -d --force-recreate <service>
```

**Verify no errors in logs:**
```bash
docker logs local-<service-name> 2>&1 | grep -iE "error|fatal|critical"
```

**Restart entire stack:**
```bash
docker compose down && docker compose up -d
```

---

## Domain

All services are exposed via subdomains on `invariantcontinuum.io`:

| Subdomain | Service |
|-----------|---------|
| `auth.` | Keycloak |
| `n8n.` | n8n |
| `pgadmin.` | PgAdmin |
| `npm.` | Nginx Proxy Manager |
| `minio.` | MinIO API |
| `minio-console.` | MinIO Console |
| `qdrant.` | Qdrant |
| `neo4j.` | Neo4j |
| `elasticsearch.` | Elasticsearch |
| `nats.` | NATS Monitoring |
| `redis.` | Redis (if proxied) |

---

*Remember: Update `home-stack-local.md` after EVERY change. Verify services start cleanly before committing.*

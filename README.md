# Local Infrastructure Stack

Complete local development stack with PostgreSQL, PgAdmin, Keycloak, n8n, and Nginx Proxy Manager.

**Domain:** `invariantcontinuum.io`

## Services

| Service | Subdomain | Local Port | Description |
|---------|-----------|------------|-------------|
| **PostgreSQL** | - | 5432 | Central relational database for all services |
| **PgAdmin** | pgadmin.invariantcontinuum.io | 5050 | Database administration UI (password-less) |
| **Keycloak** | keycloak.invariantcontinuum.io | 8080 | Identity & Access Management |
| **n8n** | n8n.invariantcontinuum.io | 5678 | Workflow automation (uses PostgreSQL) |
| **Nginx Proxy Manager** | npm.invariantcontinuum.io | 81 | Reverse proxy & SSL management |

## Database Configuration

All databases are hosted in the central PostgreSQL instance:

| Database | User | Purpose |
|----------|------|---------|
| `postgres` | `postgres` | Main admin database |
| `n8n` | `n8n` | n8n workflow automation data |
| `keycloak` | `keycloak` | Keycloak IAM data |

## Quick Start

### Using Make (Recommended)

```bash
# Deploy everything (services + IaC provisioning)
make deploy

# Or step by step:
make up        # Start services
make provision # Run IaC provisioning (creates proxy hosts)
```

### Using Docker Compose Directly

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env if needed (defaults to invariantcontinuum.io)

# 2. Start core services
docker compose up -d

# 3. Wait for services to be healthy (~60 seconds)
docker compose ps

# 4. Run IaC provisioning (creates proxy hosts automatically)
docker compose --profile provision up -d npm-provisioner

# 5. Check provisioner logs
docker compose --profile provision logs npm-provisioner
```

## IaC Provisioning

The stack includes **Infrastructure as Code** provisioning via the `npm-provisioner` service:

- **Automatically configures** Nginx Proxy Manager via REST API
- **Creates proxy hosts** for all services:
  - `pgadmin.invariantcontinuum.io` → pgadmin:80
  - `keycloak.invariantcontinuum.io` → keycloak:8080
  - `n8n.invariantcontinuum.io` → n8n:5678
  - `npm.invariantcontinuum.io` → nginx-proxy-manager:81
- **Idempotent** - can be run multiple times safely
- **Sets admin credentials** from environment variables

### Provision Manually

```bash
# Using Make
make provision

# Or using Docker Compose
docker compose --profile provision up npm-provisioner
```

## Access URLs

### Via Domain (requires /etc/hosts or DNS)
```
http://pgadmin.invariantcontinuum.io
http://keycloak.invariantcontinuum.io
http://n8n.invariantcontinuum.io
http://npm.invariantcontinuum.io
```

Add to `/etc/hosts`:
```
127.0.0.1 pgadmin.invariantcontinuum.io keycloak.invariantcontinuum.io n8n.invariantcontinuum.io npm.invariantcontinuum.io
```

### Via Localhost
```
http://localhost:5050    # PgAdmin
http://localhost:8080    # Keycloak
http://localhost:5678    # n8n
http://localhost:81      # NPM Admin
```

## Default Credentials

### PgAdmin (Password-less Mode)
- **Email:** `admin@invariantcontinuum.io`
- **Password:** `changeme` (from .env)
- **Master Password:** Not required (disabled)

### Keycloak
- **Admin Console:** http://localhost:8080/admin
- **User:** `admin`
- **Password:** `changeme` (from .env)
- **Realm:** `invariant` (auto-imported)

### n8n
- **Email:** `admin@invariantcontinuum.io`
- **Password:** `changeme` (from .env)

### Nginx Proxy Manager
- **Email:** `admin@invariantcontinuum.io`
- **Password:** `changeme` (from .env)

## PostgreSQL Access

All databases are pre-configured in PgAdmin. To connect manually:

```
Host: localhost
Port: 5432
Database: postgres | n8n | keycloak
Username: postgres | n8n | keycloak
Password: changeme (from .env)
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN_NAME` | Base domain | `invariantcontinuum.io` |
| `ADMIN_EMAIL` | Admin email for all services | `admin@invariantcontinuum.io` |
| `ADMIN_PASSWORD` | Admin password for all services | `changeme` |
| `POSTGRES_PASSWORD` | PostgreSQL superuser password | `changeme` |
| `N8N_DB_PASSWORD` | n8n database password | `changeme` |
| `KC_DB_PASSWORD` | Keycloak database password | `changeme` |
| `N8N_ENCRYPTION_KEY` | n8n encryption key | `changeme` |

## Makefile Commands

```bash
make help       # Show all available commands
make up         # Start all services
make provision  # Run IaC provisioning
make deploy     # Start services and provision (full deploy)
make down       # Stop all services
make reset      # Stop and remove all data (WARNING: destructive!)
make logs       # View logs from all services
make status     # Check service status
make test       # Test all services are accessible
make clean      # Remove unused Docker resources
```

## Docker Compose Commands

```bash
# Start all core services
docker compose up -d

# Run IaC provisioning
docker compose --profile provision up -d npm-provisioner

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f postgres
docker compose logs -f n8n
docker compose logs -f keycloak

# Stop all services
docker compose --profile provision down

# Stop and remove all data (WARNING: deletes everything!)
docker compose --profile provision down -v

# Restart a service
docker compose restart n8n

# Check service health
docker compose ps
```

## Data Persistence

- `services/postgres/volumes/data/` - PostgreSQL data
- `services/postgres/volumes/pgadmin/` - PgAdmin data
- `services/n8n/` - n8n workflows (SQLite for workflows, PostgreSQL for execution data)
- `services/nginx-proxy-manager/data/` - NPM config
- `services/nginx-proxy-manager/letsencrypt/` - SSL certificates

## Troubleshooting

### Services not starting
```bash
make logs
# or
docker compose logs -f
```

### Database connection issues
Ensure PostgreSQL is healthy before other services start:
```bash
docker compose logs postgres
```

### PgAdmin shows no servers
Servers are auto-configured via `servers.json`. If missing:
1. Log into PgAdmin
2. Right-click "Servers" → "Register" → "Server"
3. Use connection details from above

### Proxy hosts not created
Check provisioner logs:
```bash
docker compose --profile provision logs npm-provisioner
```

Re-run provisioning:
```bash
make provision
```

### n8n database errors
Ensure the n8n database and schema are created:
```bash
docker compose logs postgres | grep "Created database"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Nginx Proxy Manager                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │
│  │ pgadmin.*   │ │ keycloak.*  │ │ n8n.*       │            │
│  │ :80         │ │ :8080       │ │ :5678       │            │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘            │
└─────────┼───────────────┼───────────────┼────────────────────┘
          │               │               │
          ▼               ▼               ▼
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Network                    │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐             │
│  │  PgAdmin   │  │  Keycloak  │  │    n8n     │             │
│  │            │  │            │  │            │             │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘             │
│        │               │               │                     │
│        └───────────────┼───────────────┘                     │
│                        │                                     │
│                        ▼                                     │
│              ┌──────────────────┐                            │
│              │    PostgreSQL    │                            │
│              │  (Central DB)    │                            │
│              └──────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

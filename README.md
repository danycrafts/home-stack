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

1. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env if needed (defaults to invariantcontinuum.io)
   ```

2. **Start all services:**
   ```bash
   docker compose up -d
   ```

3. **Wait for services to be healthy (about 60 seconds):**
   ```bash
   docker compose ps
   ```

4. **Access services via localhost:**
   - PgAdmin: http://localhost:5050
   - Keycloak: http://localhost:8080
   - n8n: http://localhost:5678
   - NPM: http://localhost:81

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

## Data Persistence

- `services/postgres/volumes/data/` - PostgreSQL data
- `services/postgres/volumes/pgadmin/` - PgAdmin data
- `services/n8n/` - n8n workflows (SQLite for workflows, PostgreSQL for execution data)
- `services/nginx-proxy-manager/data/` - NPM config
- `services/nginx-proxy-manager/letsencrypt/` - SSL certificates

## Useful Commands

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f postgres
docker compose logs -f n8n
docker compose logs -f keycloak

# Stop all services
docker compose down

# Stop and remove all data (WARNING: deletes everything!)
docker compose down -v

# Restart a service
docker compose restart n8n

# Check service health
docker compose ps
```

## Troubleshooting

### Services not starting
Check logs: `docker compose logs -f`

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

### n8n database errors
Ensure the n8n database and schema are created:
```bash
docker compose logs postgres | grep "Created database"
```

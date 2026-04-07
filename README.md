# Local Infrastructure

Local development stack with PostgreSQL, PgAdmin, n8n, and Nginx Proxy Manager.

**Domain:** `invariantcontinuum.io`

## Services

| Service | Subdomain | Local Port | Description |
|---------|-----------|------------|-------------|
| **PostgreSQL** | - | 5432 | Relational database |
| **PgAdmin** | pgadmin.invariantcontinuum.io | 5050 | Database administration UI |
| **n8n** | n8n.invariantcontinuum.io | 5678 | Workflow automation |
| **Nginx Proxy Manager** | npm.invariantcontinuum.io | 81 | Reverse proxy & SSL |

## Quick Start

1. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env if needed (defaults to invariantcontinuum.io)
   ```

## Access URLs

### Via Domain (requires /etc/hosts or DNS)
```
http://pgadmin.invariantcontinuum.io
http://n8n.invariantcontinuum.io
http://npm.invariantcontinuum.io
```

Add to `/etc/hosts`:
```
127.0.0.1 pgadmin.invariantcontinuum.io n8n.invariantcontinuum.io npm.invariantcontinuum.io
```

### Via Localhost
```
http://localhost:5050    # PgAdmin
http://localhost:5678    # n8n
http://localhost:81      # NPM Admin
```

### Default Credentials

**PgAdmin:**
- Email: `admin@invariantcontinuum.io`
- Password: (from .env, default: changeme)

**n8n:**
- User: `admin`
- Password: (from .env, default: changeme)

**Nginx Proxy Manager:**
- Email: `admin@invariantcontinuum.io`
- Password: (from .env, default: changeme)

## Usage

```bash
./local-start.sh        # Start all services
docker compose down     # Stop all services
docker compose logs -f  # View logs
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN_NAME` | Base domain | `invariantcontinuum.io` |
| `N8N_SUBDOMAIN` | n8n subdomain | `n8n` |
| `PGADMIN_SUBDOMAIN` | PgAdmin subdomain | `pgadmin` |
| `NPM_ADMIN_SUBDOMAIN` | NPM admin subdomain | `npm` |

## Data Persistence

- `services/postgres/volumes/data/` - PostgreSQL data
- `services/postgres/volumes/pgadmin/` - PgAdmin data
- `services/n8n/` - n8n workflows
- `services/nginx-proxy-manager/data/` - NPM config
- `services/nginx-proxy-manager/letsencrypt/` - SSL certificates

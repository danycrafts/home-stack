# Local Infrastructure

Local development stack with PostgreSQL, PgAdmin, n8n, and Nginx Proxy Manager.

**Domain:** `your-domain.com`

## Services

| Service | Subdomain | Local Port | Description |
|---------|-----------|------------|-------------|
| **PostgreSQL** | - | 5432 | Relational database |
| **PgAdmin** | pgadmin.your-domain.com | 5050 | Database administration UI |
| **n8n** | n8n.your-domain.com | 5678 | Workflow automation |
| **Nginx Proxy Manager** | npm.your-domain.com | 81 | Reverse proxy & SSL |

## Quick Start

1. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env if needed (defaults to your-domain.com)
   ```

## Access URLs

### Via Domain (requires /etc/hosts or DNS)
```
http://pgadmin.your-domain.com
http://n8n.your-domain.com
http://npm.your-domain.com
```

Add to `/etc/hosts`:
```
127.0.0.1 pgadmin.your-domain.com n8n.your-domain.com npm.your-domain.com
```

### Via Localhost
```
http://localhost:5050    # PgAdmin
http://localhost:5678    # n8n
http://localhost:81      # NPM Admin
```

### Default Credentials

**PgAdmin:**
- Email: `admin@your-domain.com`
- Password: (from .env, default: changeme)

**n8n:**
- User: `admin`
- Password: (from .env, default: changeme)

**Nginx Proxy Manager:**
- Email: `admin@your-domain.com`
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
| `DOMAIN_NAME` | Base domain | `your-domain.com` |
| `N8N_SUBDOMAIN` | n8n subdomain | `n8n` |
| `PGADMIN_SUBDOMAIN` | PgAdmin subdomain | `pgadmin` |
| `NPM_ADMIN_SUBDOMAIN` | NPM admin subdomain | `npm` |

## Data Persistence

- `services/postgres/volumes/data/` - PostgreSQL data
- `services/postgres/volumes/pgadmin/` - PgAdmin data
- `services/n8n/` - n8n workflows
- `services/nginx-proxy-manager/data/` - NPM config
- `services/nginx-proxy-manager/letsencrypt/` - SSL certificates

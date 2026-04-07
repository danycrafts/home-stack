# Home Stack - Local Service Documentation

> **WARNING:** This file contains plain-text credentials. Keep it local - DO NOT commit to git.
> Location: `~/github/danycrafts/home-stack/home-stack-local.md`

---

## Quick Reference

| Service | URL | Port | Purpose |
|---------|-----|------|---------|
| **Nginx Proxy Manager** | https://npm.invariantcontinuum.io | 81 | Reverse proxy management |
| **Keycloak** | https://auth.invariantcontinuum.io | 8080 | Identity & Access Management |
| **n8n** | https://n8n.invariantcontinuum.io | 5678 | Workflow automation |
| **PgAdmin** | https://pgadmin.invariantcontinuum.io | 5050 | PostgreSQL management |
| **Redis Commander** | http://localhost:8081 | 8081 | Redis GUI (no NPM proxy) |
| **MinIO API** | https://minio.invariantcontinuum.io | 9000 | S3-compatible object storage |
| **MinIO Console** | https://minio-console.invariantcontinuum.io | 9001 | MinIO web UI |
| **Qdrant** | https://qdrant.invariantcontinuum.io | 6333 | Vector database |
| **Neo4j Browser** | https://neo4j.invariantcontinuum.io | 7474 | Graph database UI |
| **Neo4j Bolt** | bolt://localhost:7687 | 7687 | Graph DB protocol |
| **Elasticsearch** | https://elasticsearch.invariantcontinuum.io | 9200 | Search & analytics |
| **NATS Monitor** | https://nats.invariantcontinuum.io | 8222 | NATS monitoring UI |
| **PostgreSQL** | localhost:5432 | 5432 | Primary database |
| **Redis** | localhost:6379 | 6379 | In-memory cache |

---

## Core Infrastructure

### PostgreSQL 16

**Container:** `local-postgres`

**Connection:**
```
Host: localhost:5432
Username: postgres
Password: changeme
Database: postgres
```

**Application Databases:**

| Database | User | Password | Used By |
|----------|------|----------|---------|
| `n8n` | n8n | changeme | n8n workflow automation |
| `keycloak` | keycloak | changeme | Keycloak IAM |

**Direct Access:**
```bash
docker exec -it local-postgres psql -U postgres
```

---

### Redis 7

**Container:** `local-redis`

**Connection:**
```
Host: localhost:6379
Password: changeme
```

**CLI Access:**
```bash
docker exec -it local-redis redis-cli -a changeme
```

**Redis Commander UI:** http://localhost:8081 (not proxied through NPM)

---

### NATS 3-Node Cluster

**Containers:** `local-nats-1`, `local-nats-2`, `local-nats-3`

**Connection:**
```
Client:   localhost:4222
HTTP:     localhost:8222
Cluster:  6222 (internal)
```

**Monitoring UI:** https://nats.invariantcontinuum.io

**Features:**
- JetStream enabled
- 3-node clustering for HA
- Message persistence enabled

---

## Application Services

### Nginx Proxy Manager

**Container:** `local-npm`

**Admin UI:** https://npm.invariantcontinuum.io

**Default Credentials:**
```
Email: admin@example.com
Password: changeme
```

**Custom Credentials:**
```
Email: admin@invariantcontinuum.io
Password: changeme
```

**Features:**
- Automatic proxy host provisioning via IaC
- SSL forced on all hosts
- HTTP/2 and HSTS enabled

---

### Keycloak

**Container:** `local-keycloak`

**Admin Console:** https://auth.invariantcontinuum.io/admin

**Master Realm Credentials:**
```
Username: admin
Password: changeme
```

**Invariant Realm Credentials:**
```
Username: admin
Password: invariant
```

**Realm:** `invariant`

**OAuth2 Endpoints:**
```
Issuer:       http://auth.invariantcontinuum.io/realms/invariant
Auth URL:     http://auth.invariantcontinuum.io/realms/invariant/protocol/openid-connect/auth
Token URL:    http://auth.invariantcontinuum.io/realms/invariant/protocol/openid-connect/token
User Info:    http://auth.invariantcontinuum.io/realms/invariant/protocol/openid-connect/userinfo
```

**Configured Clients:**

| Client ID | Client Secret | Used By |
|-----------|--------------|---------|
| `n8n` | `n8n-client-secret` | n8n OAuth |
| `pgadmin` | `pgadmin-client-secret` | PgAdmin OAuth |

**Identity Providers:**
- GitHub OAuth (configured in invariant realm)

---

### n8n

**Container:** `local-n8n`

**URL:** https://n8n.invariantcontinuum.io

**Authentication:** OAuth2 via Keycloak (basic auth disabled)

**Database:** PostgreSQL (`n8n` database)

**Features:**
- External OAuth enabled
- Workflow automation platform

---

### PgAdmin

**Container:** `local-pgadmin`

**URL:** https://pgadmin.invariantcontinuum.io

**Authentication:** OAuth2 via Keycloak + internal fallback

**Pre-configured Servers:**

| Server Name | Host | Database | Username |
|-------------|------|----------|----------|
| PostgreSQL - Admin | postgres | postgres | postgres |
| n8n Database | postgres | n8n | n8n |
| Keycloak Database | postgres | keycloak | keycloak |

**Password-less Auth:** Configured via pgpass file

---

## Data Services

### MinIO

**Container:** `local-minio`

**S3 API:** https://minio.invariantcontinuum.io (port 9000)
**Web Console:** https://minio-console.invariantcontinuum.io (port 9001)

**Root Credentials:**
```
Access Key: minioadmin
Secret Key: changeme
```

**Features:**
- S3-compatible object storage
- Web-based management console
- Bucket policies and access controls

---

### Qdrant

**Container:** `local-qdrant`

**REST API:** https://qdrant.invariantcontinuum.io
**gRPC:** localhost:6334

**Features:**
- Vector similarity search
- Collections management
- REST and gRPC APIs

**Health Check:** http://localhost:6333/readyz

---

### Neo4j

**Container:** `local-neo4j`

**Browser:** https://neo4j.invariantcontinuum.io
**Bolt Protocol:** bolt://localhost:7687

**Credentials:**
```
Username: neo4j
Password: changeme
```

**Plugins:**
- APOC (Awesome Procedures On Cypher)

**Configuration:**
- Heap size: 512m
- Security procedures unrestricted for APOC

**Cypher Shell:**
```bash
docker exec -it local-neo4j cypher-shell -u neo4j -p changeme
```

---

### Elasticsearch

**Container:** `local-elasticsearch`

**URL:** https://elasticsearch.invariantcontinuum.io

**Configuration:**
- Single node mode
- Security disabled (xpack.security.enabled=false)
- Heap size: 512m

**Health Check:**
```bash
curl http://localhost:9200/_cluster/health
```

**Features:**
- Full-text search engine
- Analytics and aggregations
- RESTful API

---

## Environment Variables

All services use environment variables from `.env` file. Key variables:

```bash
# Domain & Admin
DOMAIN_NAME=invariantcontinuum.io
ADMIN_EMAIL=admin@invariantcontinuum.io
ADMIN_PASSWORD=changeme
ADMIN_USER=admin

# PostgreSQL
POSTGRES_PASSWORD=changeme
N8N_DB_PASSWORD=changeme
KC_DB_PASSWORD=changeme

# Redis
REDIS_PASSWORD=changeme

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=changeme

# Neo4j
NEO4J_AUTH=neo4j/changeme

# Keycloak (Invariant Realm Admin)
KC_ADMIN_USER=admin
KC_ADMIN_PASSWORD=invariant
```

---

## Useful Commands

### Start/Stop Stack

```bash
# Start all services
docker compose up -d

# Start specific group
docker compose -f core/postgres.yml up -d
docker compose -f apps/keycloak.yml up -d

# View logs
docker compose logs -f [service-name]

# Restart service
docker compose restart [service-name]

# Stop all
docker compose down

# Stop and remove volumes (WARNING: data loss)
docker compose down -v
```

### Container Management

```bash
# List all home-stack containers
docker ps --filter name=local-

# Shell into container
docker exec -it local-postgres /bin/sh
docker exec -it local-keycloak /bin/bash

# View container logs
docker logs -f local-n8n
```

### Database Backups

```bash
# Backup PostgreSQL
docker exec local-postgres pg_dump -U postgres -d n8n > n8n_backup.sql
docker exec local-postgres pg_dump -U postgres -d keycloak > keycloak_backup.sql

# Restore PostgreSQL
docker exec -i local-postgres psql -U postgres -d n8n < n8n_backup.sql
```

---

## Network & Volumes

### Network
- **Name:** `local-infra-network`
- **Driver:** bridge
- **All services communicate via this network**

### Named Volumes

| Volume Name | Container Path | Service |
|-------------|----------------|---------|
| local-postgres-data | /var/lib/postgresql/data | PostgreSQL |
| local-pgadmin-data | /var/lib/pgadmin | PgAdmin |
| local-n8n-data | /home/node/.n8n | n8n |
| local-npm-data | /data | NPM |
| local-npm-letsencrypt | /etc/letsencrypt | NPM SSL |
| local-redis-data | /data | Redis |
| local-minio-data | /data | MinIO |
| local-qdrant-data | /qdrant/storage | Qdrant |
| local-neo4j-data | /data | Neo4j |
| local-es-data | /usr/share/elasticsearch/data | Elasticsearch |
| local-nats-data | /data/jetstream | NATS Node 1 |
| local-nats-data-2 | /data/jetstream | NATS Node 2 |
| local-nats-data-3 | /data/jetstream | NATS Node 3 |

---

## Troubleshooting

### Common Issues

**PostgreSQL connection refused:**
```bash
docker compose -f core/postgres.yml restart postgres
```

**Keycloak won't start:**
```bash
# Check if postgres is healthy first
docker compose -f core/postgres.yml ps

# Restart keycloak
docker compose -f apps/keycloak.yml restart keycloak
```

**NPM proxy hosts not created:**
```bash
# Re-run provisioner
docker compose -f apps/nginx-proxy-manager.yml run --rm npm-provisioner
```

**Redis connection issues:**
```bash
# Test connection
docker exec -it local-redis redis-cli -a changeme ping
```

**Elasticsearch memory issues:**
```bash
# Check ES heap usage
curl http://localhost:9200/_nodes/stats/jvm?pretty
```

---

## File Structure

```
home-stack/
├── docker-compose.yml              # Main orchestrator
├── .env                            # Environment variables (git-ignored)
├── .env.example                    # Example environment file
├── home-stack-local.md             # This file
├── AGENTS.md                       # Agent instructions
├── core/                           # Core infrastructure
│   ├── postgres.yml
│   ├── redis.yml
│   └── nats.yml
├── apps/                           # Application services
│   ├── nginx-proxy-manager.yml
│   ├── keycloak.yml
│   ├── n8n.yml
│   └── pgadmin.yml
├── data/                           # Data stores
│   ├── minio.yml
│   ├── qdrant.yml
│   ├── neo4j.yml
│   └── elasticsearch.yml
└── services/                       # Service configurations
    ├── postgres/init/
    ├── keycloak/
    ├── pgadmin/
    └── nginx-proxy-manager/
```

---

*Last updated: 2026-04-07*
*Domain: invariantcontinuum.io*

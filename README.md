# Home Stack

Clean infrastructure stack for `invariantcontinuum.io`.

The stack intentionally uses plain Nginx instead of Nginx Proxy Manager. Nginx is built from `services/nginx/Dockerfile`, includes certbot, runs cron for renewal and log rotation, mounts file-based server configs from `services/nginx/conf.d`, and exposes a `/healthz` endpoint for Compose health checks.

## Services

| Service | Domain or endpoint | Notes |
| --- | --- | --- |
| Nginx | `https://nginx.invariantcontinuum.io` | Load balancer, health endpoint, certbot renewal, log rotation |
| Keycloak | `https://auth.invariantcontinuum.io` | Empty realm state by default; realm/theme mount points are provided |
| pgAdmin | `https://pgadmin.invariantcontinuum.io` | Connects to the internal Postgres service |
| Redis Commander | `https://redis.invariantcontinuum.io` | UI for Redis |
| SSH | `sh.invariantcontinuum.io:443` | SSH pass-through to this host's port 22 through Nginx stream |
| Postgres | `postgres.invariantcontinuum.io:5432` | TCP pass-through through Nginx stream |
| Redis | `redis.invariantcontinuum.io:6379` | TCP pass-through through Nginx stream |

## Layout

```text
services/nginx/
├── Dockerfile
├── conf.d/              # one HTTP server file per routed domain
├── snippets/proxy.conf  # shared reverse proxy headers/timeouts
├── snippets/ssl.conf    # shared TLS policy
├── stream.conf          # TCP pass-through routing, including 443 TLS/SSH multiplexing
├── certbot/www/         # ACME webroot
├── letsencrypt/         # mounted Let's Encrypt state
└── logs/                # mounted Nginx access/error logs
```

## Database Creation

Postgres creates additional databases from the space-separated `POSTGRES_DATABASES` value. Each database gets a user with the same name and the password from `POSTGRES_DATABASE_PASSWORD`, which defaults to `changeme`.

```env
POSTGRES_DATABASES="keycloak app analytics"
POSTGRES_DATABASE_PASSWORD=changeme
```

Database names must use letters, numbers, and underscores and cannot start with a number.

## Keycloak Mounts

The Keycloak container starts empty. These paths are mounted for later use:

- `services/keycloak/realm.conf` -> `/opt/keycloak/conf/realm.conf`
- `services/keycloak/import/` -> `/opt/keycloak/data/import/`
- `services/keycloak/themes/custom/` -> `/opt/keycloak/themes/custom/`

## Commands

```bash
make up       # build and start all services
make certs    # request/renew certificates for CERTBOT_DOMAINS
make test     # validate compose and local health checks
make status   # show containers
make logs     # follow logs
make reset    # stop services and remove volumes
```

The first boot creates short-lived self-signed placeholder certificates so Nginx can start before certbot issues real certificates. Run `make certs` after DNS for the configured domains points at this host.

Port 443 is fronted by the Nginx stream module. TLS handshakes are routed to the internal HTTPS listeners on port 8443, while non-TLS SSH connections to `sh.invariantcontinuum.io:443` are routed to the host SSH daemon on port 22.

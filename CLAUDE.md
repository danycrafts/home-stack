# CLAUDE.md - Local Infrastructure

## Post-Change Policy
After any successful change to service configuration (docker-compose.yml, environment files, service configs), always recreate the affected services using `docker compose up -d --force-recreate <service>` to apply changes immediately.

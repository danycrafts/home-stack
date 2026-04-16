#!/bin/bash
# =============================================================================
# Initialize Nginx Proxy Manager via REST API (IaC)
# All proxy hosts use HTTPS with SSL forced
# =============================================================================
set -e

NPM_URL="http://nginx-proxy-manager:81"
DOMAIN="${DOMAIN_NAME:-invariantcontinuum.io}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@invariantcontinuum.io}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-changeme}"

# Subdomains
PGADMIN_SUBDOMAIN="${PGADMIN_SUBDOMAIN:-pgadmin}"
KC_SUBDOMAIN="${KC_SUBDOMAIN:-auth}"
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"
NPM_SUBDOMAIN="${NPM_ADMIN_SUBDOMAIN:-npm}"
MINIO_SUBDOMAIN="${MINIO_SUBDOMAIN:-minio}"
MINIO_CONSOLE_SUBDOMAIN="${MINIO_CONSOLE_SUBDOMAIN:-minio-console}"
ELASTIC_SUBDOMAIN="${ELASTIC_SUBDOMAIN:-elasticsearch}"
NATS_SUBDOMAIN="${NATS_SUBDOMAIN:-nats}"
REDIS_COMMANDER_SUBDOMAIN="${REDIS_COMMANDER_SUBDOMAIN:-redis-ui}"

echo "============================================================================="
echo "  NPM IaC Provisioner"
echo "  Domain: ${DOMAIN}"
echo "  HTTPS: Enabled (SSL Forced)"
echo "============================================================================="
echo ""

echo "⏳ Waiting for Nginx Proxy Manager API..."
until curl -sf "${NPM_URL}/api/" >/dev/null 2>&1; do
    sleep 3
done
echo "✓ NPM API is ready"
echo ""

# ─── Authenticate (try custom creds first, fall back to defaults) ──────────────
get_token() {
    local email=$1
    local pass=$2
    curl -sf -X POST "${NPM_URL}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${email}\",\"secret\":\"${pass}\"}" 2>/dev/null \
        | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

echo "🔐 Authenticating..."
TOKEN=$(get_token "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}")
if [ -z "$TOKEN" ]; then
    echo "  → Trying default NPM credentials..."
    TOKEN=$(get_token "admin@example.com" "changeme")
    if [ -z "$TOKEN" ]; then
        echo "ERROR: Cannot authenticate with NPM" >&2
        exit 1
    fi
    echo "  ✓ Logged in with default credentials"

    # Update admin user to our desired email/password
    echo "  → Updating admin credentials..."
    USER_ID=$(curl -sf "${NPM_URL}/api/users" \
        -H "Authorization: Bearer ${TOKEN}" | \
        grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')

    curl -sf -X PUT "${NPM_URL}/api/users/${USER_ID}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"Admin\",\"nickname\":\"admin\",\"email\":\"${ADMIN_EMAIL}\",\"roles\":[\"admin\"]}" >/dev/null

    curl -sf -X PUT "${NPM_URL}/api/users/${USER_ID}/auth" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"password\",\"current\":\"changeme\",\"secret\":\"${ADMIN_PASSWORD}\"}" >/dev/null

    echo "  ✓ Admin credentials updated to ${ADMIN_EMAIL}"

    # Re-authenticate with new credentials
    TOKEN=$(get_token "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}")
fi

echo "✓ Authenticated as ${ADMIN_EMAIL}"
echo ""

# ─── Helper: request Let's Encrypt certificate ───────────────────────────────
request_letsencrypt_cert() {
    local fqdn=$1

    # Check if cert already exists
    existing_cert=$(curl -sf "${NPM_URL}/api/nginx/certificates" \
        -H "Authorization: Bearer ${TOKEN}" | \
        grep -o "\"${fqdn}\"" | head -1 || echo "")

    if [ -n "$existing_cert" ]; then
        # Return existing cert ID
        curl -sf "${NPM_URL}/api/nginx/certificates" \
            -H "Authorization: Bearer ${TOKEN}" | \
            python3 -c "import sys,json; certs=json.load(sys.stdin); [print(c['id']) for c in certs if '${fqdn}' in c.get('domain_names',[])]" 2>/dev/null | head -1
        return 0
    fi

    # Request new Let's Encrypt certificate
    cert_response=$(curl -sf -X POST "${NPM_URL}/api/nginx/certificates" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\":[\"${fqdn}\"],
            \"meta\":{},
            \"provider\":\"letsencrypt\"
        }" 2>&1)

    echo "$cert_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
}

# ─── Helper: get proxy host ID by FQDN ───────────────────────────────────────
get_proxy_host_id() {
    local fqdn=$1
    curl -sf "${NPM_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${TOKEN}" | \
        python3 -c "import sys,json; hosts=json.load(sys.stdin); [print(h['id']) for h in hosts if '${fqdn}' in h.get('domain_names',[])]" 2>/dev/null | head -1
}

# ─── Helper: create or update proxy host with HTTPS + Let's Encrypt ──────────
create_proxy_host_https() {
    local subdomain=$1
    local forward_host=$2
    local forward_port=$3
    local advanced_config="${4:-}"
    local fqdn="${subdomain}.${DOMAIN}"

    # Request Let's Encrypt certificate
    echo "  ⏳ Requesting Let's Encrypt cert for ${fqdn}..."
    cert_id=$(request_letsencrypt_cert "${fqdn}")

    # Build certificate_id field if cert was obtained
    local cert_field=""
    if [ -n "$cert_id" ] && [ "$cert_id" != "null" ]; then
        cert_field="\"certificate_id\":${cert_id},"
        echo "  🔒 Certificate obtained (ID: ${cert_id})"
    else
        echo "  ⚠  Certificate request failed, proceeding without SSL cert"
    fi

    # Build advanced_config field
    local adv_field=""
    if [ -n "$advanced_config" ]; then
        # Escape newlines and quotes for JSON
        local escaped_config
        escaped_config=$(echo "$advanced_config" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || echo "\"\"")
        adv_field="\"advanced_config\":${escaped_config},"
    fi

    # Check if proxy host already exists
    host_id=$(get_proxy_host_id "${fqdn}")

    if [ -n "$host_id" ] && [ "$host_id" != "null" ]; then
        echo "  🔄 Updating existing proxy host ${fqdn} (ID: ${host_id})..."
        curl -sf -X PUT "${NPM_URL}/api/nginx/proxy-hosts/${host_id}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\":[\"${fqdn}\"],
                \"forward_scheme\":\"http\",
                \"forward_host\":\"${forward_host}\",
                \"forward_port\":${forward_port},
                ${cert_field}
                ${adv_field}
                \"block_exploits\":true,
                \"allow_websocket_upgrade\":true,
                \"http2_support\":true,
                \"caching_enabled\":true,
                \"ssl_forced\":true,
                \"hsts_enabled\":true,
                \"hsts_subdomains\":true,
                \"trust_forwarded_proto\":true,
                \"enabled\":true,
                \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
            }" >/dev/null
        echo "  ✓ ${fqdn} → ${forward_host}:${forward_port} (updated, HTTPS + Let's Encrypt)"
    else
        echo "  🆕 Creating proxy host ${fqdn}..."
        curl -sf -X POST "${NPM_URL}/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\":[\"${fqdn}\"],
                \"forward_scheme\":\"http\",
                \"forward_host\":\"${forward_host}\",
                \"forward_port\":${forward_port},
                ${cert_field}
                ${adv_field}
                \"block_exploits\":true,
                \"allow_websocket_upgrade\":true,
                \"http2_support\":true,
                \"caching_enabled\":true,
                \"ssl_forced\":true,
                \"hsts_enabled\":true,
                \"hsts_subdomains\":true,
                \"trust_forwarded_proto\":true,
                \"enabled\":true,
                \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
            }" >/dev/null
        echo "  ✓ ${fqdn} → ${forward_host}:${forward_port} (created, HTTPS + Let's Encrypt)"
    fi
}

# ─── Create proxy hosts with HTTPS ────────────────────────────────────────────
echo "🌐 Provisioning proxy hosts for domain: ${DOMAIN}"
echo "   (SSL Forced, HTTP/2, HSTS, Caching enabled)"
echo ""

echo "┌─ Core Services ──────────────────────────────────────────────────────────┐"
create_proxy_host_https "${PGADMIN_SUBDOMAIN}" "pgadmin" 80
create_proxy_host_https "${KC_SUBDOMAIN}"      "keycloak" 8080
create_proxy_host_https "${N8N_SUBDOMAIN}"     "n8n"     5678
create_proxy_host_https "${NPM_SUBDOMAIN}"     "nginx-proxy-manager" 81
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""

echo "┌─ Platform Services ────────────────────────────────────────────────────┐"
# Substrate platform: NPM proxies only the frontend (app.*) and Keycloak
# (auth.*). The gateway, graph-service and ingestion are reachable only
# over the host network via localhost; the frontend's nginx proxies
# /api, /jobs, /ingest, /auth and /ws to the gateway on the host port.
# Advanced nginx config for app: prevent internal port 3000 from leaking in
# redirects and ensure X-Forwarded-Port is set to 443 for the backend.
APP_ADVANCED_CONFIG='proxy_redirect http://$host:3000/ /;
proxy_redirect https://$host:3000/ /;
proxy_redirect http://$host:3000 /;
proxy_redirect https://$host:3000 /;
proxy_set_header X-Forwarded-Port 443;'

create_proxy_host_https "app" "substrate-frontend" 3000 "$APP_ADVANCED_CONFIG"
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""

echo "┌─ Data Services ──────────────────────────────────────────────────────────┐"
create_proxy_host_https "${REDIS_COMMANDER_SUBDOMAIN}" "redis-commander" 8081
create_proxy_host_https "${MINIO_SUBDOMAIN}"          "minio"          9000
create_proxy_host_https "${MINIO_CONSOLE_SUBDOMAIN}"  "minio"          9001
create_proxy_host_https "${ELASTIC_SUBDOMAIN}"        "elasticsearch"  9200
create_proxy_host_https "${NATS_SUBDOMAIN}"           "nats-1"         8222
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""

echo "============================================================================="
echo "  ✓ IaC Provisioning Complete"
echo "============================================================================="
echo ""
echo "Access your services (HTTPS):"
echo ""
echo "Core:"
echo "  → https://${PGADMIN_SUBDOMAIN}.${DOMAIN}"
echo "  → https://${KC_SUBDOMAIN}.${DOMAIN}"
echo "  → https://${N8N_SUBDOMAIN}.${DOMAIN}"
echo "  → https://${NPM_SUBDOMAIN}.${DOMAIN}"
echo ""
echo "Platform:"
echo "  → https://app.${DOMAIN}                (Substrate Frontend)"
echo ""
echo "Data Services:"
echo "  → https://${REDIS_COMMANDER_SUBDOMAIN}.${DOMAIN}   (Redis Commander)"
echo "  → https://${MINIO_SUBDOMAIN}.${DOMAIN}        (MinIO API)"
echo "  → https://${MINIO_CONSOLE_SUBDOMAIN}.${DOMAIN} (MinIO Console)"
echo "  → https://${ELASTIC_SUBDOMAIN}.${DOMAIN}      (Elasticsearch)"
echo "  → https://${NATS_SUBDOMAIN}.${DOMAIN}         (NATS Monitoring)"
echo ""
echo "NATS Cluster (Client ports):"
echo "  → localhost:4222 (Node 1)"
echo "  → localhost:4223 (Node 2)"
echo "  → localhost:4224 (Node 3)"
echo ""
echo "Note: SSL certificates must be configured separately via NPM UI"
echo "      or use Let's Encrypt DNS challenge for automatic certificates."
echo ""

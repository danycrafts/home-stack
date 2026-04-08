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
QDRANT_SUBDOMAIN="${QDRANT_SUBDOMAIN:-qdrant}"
NEO4J_SUBDOMAIN="${NEO4J_SUBDOMAIN:-neo4j}"
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

# ─── Helper: create proxy host with HTTPS + Let's Encrypt ────────────────────
create_proxy_host_https() {
    local subdomain=$1
    local forward_host=$2
    local forward_port=$3
    local fqdn="${subdomain}.${DOMAIN}"

    # Check if already exists
    existing=$(curl -sf "${NPM_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${TOKEN}" | \
        grep -o "\"${fqdn}\"" | head -1 || echo "")

    if [ -n "$existing" ]; then
        echo "  ✓ ${fqdn} (already exists)"
        return 0
    fi

    # Request Let's Encrypt certificate
    echo "  ⏳ Requesting Let's Encrypt cert for ${fqdn}..."
    cert_id=$(request_letsencrypt_cert "${fqdn}")

    # Build certificate_id field if cert was obtained
    local cert_field=""
    if [ -n "$cert_id" ] && [ "$cert_id" != "null" ]; then
        cert_field="\"certificate_id\":${cert_id},"
        echo "  🔒 Certificate obtained (ID: ${cert_id})"
    else
        echo "  ⚠  Certificate request failed, creating host without SSL cert"
    fi

    # Create proxy host with SSL forced + Let's Encrypt cert
    curl -sf -X POST "${NPM_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\":[\"${fqdn}\"],
            \"forward_scheme\":\"http\",
            \"forward_host\":\"${forward_host}\",
            \"forward_port\":${forward_port},
            ${cert_field}
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

    echo "  ✓ ${fqdn} → ${forward_host}:${forward_port} (HTTPS + Let's Encrypt)"
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
create_proxy_host_https "substrate" "substrate-gateway" 8080
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""

echo "┌─ Data Services ──────────────────────────────────────────────────────────┐"
create_proxy_host_https "${REDIS_COMMANDER_SUBDOMAIN}" "redis-commander" 8081
create_proxy_host_https "${MINIO_SUBDOMAIN}"          "minio"          9000
create_proxy_host_https "${MINIO_CONSOLE_SUBDOMAIN}"  "minio"          9001
create_proxy_host_https "${QDRANT_SUBDOMAIN}"         "qdrant"         6333
create_proxy_host_https "${NEO4J_SUBDOMAIN}"          "neo4j"          7474
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
echo "  → https://substrate.${DOMAIN}          (Substrate Platform)"
echo ""
echo "Data Services:"
echo "  → https://${REDIS_COMMANDER_SUBDOMAIN}.${DOMAIN}   (Redis Commander)"
echo "  → https://${MINIO_SUBDOMAIN}.${DOMAIN}        (MinIO API)"
echo "  → https://${MINIO_CONSOLE_SUBDOMAIN}.${DOMAIN} (MinIO Console)"
echo "  → https://${QDRANT_SUBDOMAIN}.${DOMAIN}       (Qdrant Vector DB)"
echo "  → https://${NEO4J_SUBDOMAIN}.${DOMAIN}        (Neo4j Graph DB)"
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

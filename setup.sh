#!/bin/bash
set -e

echo "Generating configuration and secrets for Authentik + Caddy..."

# Prompt for Base Domain
read -p "Base Domain (e.g., example.com): " BASE_DOMAIN
if [ -z "$BASE_DOMAIN" ]; then
    echo "Base domain is required. Exiting."
    exit 1
fi

# Prompt for Authentik Admin Username
read -p "Enter Authentik Admin Username (default: akadmin): " AUTHENTIK_ADMIN_USER
if [ -z "$AUTHENTIK_ADMIN_USER" ]; then
    AUTHENTIK_ADMIN_USER="akadmin"
fi

# Prompt for Authentik Admin Password
read -p "Enter Authentik Admin Password (leave blank for auto-generated): " AUTHENTIK_ADMIN_PASSWORD
if [ -z "$AUTHENTIK_ADMIN_PASSWORD" ]; then
    # Generate readable hex password
    AUTHENTIK_ADMIN_PASSWORD=$(openssl rand -hex 12)
fi

# Generate secrets
PG_PASS=$(openssl rand -base64 36 | tr -d '\n')
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
CADDY_JWT_SECRET=$(openssl rand -hex 32)
AUTHENTIK_BOOTSTRAP_TOKEN=$(openssl rand -hex 40)

# Create necessary directories
mkdir -p caddy_config
mkdir -p certs

# Generate .env file
cat > .env << EOF
# Domain Configuration
BASE_DOMAIN=$BASE_DOMAIN

# Postgres Configuration
PG_PASS=$PG_PASS
PG_USER=authentik
PG_DB=authentik

# Authentik Configuration
AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY
AUTHENTIK_ADMIN_USER=$AUTHENTIK_ADMIN_USER
AUTHENTIK_ADMIN_EMAIL=admin@example.com
AUTHENTIK_ADMIN_PASSWORD=$AUTHENTIK_ADMIN_PASSWORD

AUTHENTIK_BOOTSTRAP_TOKEN=$AUTHENTIK_BOOTSTRAP_TOKEN

# Caddy Configuration
CADDY_JWT_SECRET=$CADDY_JWT_SECRET
EOF

echo "Setup completed successfully!"
echo ""
echo "Authentik Admin Credentials:"
echo "- username: $AUTHENTIK_ADMIN_USER"
echo "- password: $AUTHENTIK_ADMIN_PASSWORD"
echo ""
echo "To start the auth system:"
echo "1. Copy your TLS certificates (or let Caddy obtain them automatically):"
echo "   cp /etc/letsencrypt/live/$BASE_DOMAIN/fullchain.pem ./certs/cert.pem"
echo "   cp /etc/letsencrypt/live/$BASE_DOMAIN/privkey.pem ./certs/key.pem"
echo ""
echo "2. Start the services:"
echo "   docker-compose up -d"
echo ""
echo "Access points:"
echo "- Authentik portal: https://auth.$BASE_DOMAIN"
echo "- Initial setup: https://auth.$BASE_DOMAIN/if/flow/initial-setup/"
echo ""
echo "Security notes:"
echo "- TLS is automatically managed by Caddy"
echo "- The initialization script will automatically create the Forward Auth provider"
echo ""
echo "To integrate with Okta later, you can add an OAuth source in the Authentik admin interface"
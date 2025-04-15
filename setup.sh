#!/bin/bash
set -e

echo "Generating configuration and secrets..."

# Prompt for Base Domain
read -p "Base Domain (e.g., example.com): " BASE_DOMAIN
if [ -z "$BASE_DOMAIN" ]; then
    echo "Base domain is required. Exiting."
    exit 1
fi

# Prompt for LLDAP Admin Password
read -p "Enter LLDAP Admin Password (leave blank for auto-generated): " LLDAP_ADMIN_PASSWORD
if [ -z "$LLDAP_ADMIN_PASSWORD" ]; then
    # Generate readable hex password instead of complex characters
    LLDAP_ADMIN_PASSWORD=$(openssl rand -hex 8)
fi

# Generate hex secrets for better readability
LLDAP_JWT_SECRET=$(openssl rand -hex 16)
LLDAP_BASE_DN=$(echo $BASE_DOMAIN | sed 's/\./,dc=/g' | sed 's/^/dc=/')
LLDAP_AUTH_PASSWORD=$(openssl rand -hex 8)

# Caddy Security specific secrets
CADDY_JWT_SECRET=$(openssl rand -hex 32)
CADDY_ENCRYPTION_KEY=$(openssl rand -hex 32)
CADDY_LDAP_BIND_USERNAME="caddy-auth"
CADDY_LDAP_BIND_PASSWORD=$(openssl rand -hex 8)

# Create necessary directories
mkdir -p caddy/auth
mkdir -p certs

# Generate .env file
cat > .env << EOF
# Domain Configuration
BASE_DOMAIN=$BASE_DOMAIN

# LLDAP Configuration
LLDAP_ADMIN_PASSWORD=$LLDAP_ADMIN_PASSWORD
LLDAP_JWT_SECRET=$LLDAP_JWT_SECRET
LLDAP_BASE_DN=$LLDAP_BASE_DN
LLDAP_AUTH_PASSWORD=$LLDAP_AUTH_PASSWORD

# Caddy Security Configuration
CADDY_JWT_SECRET=$CADDY_JWT_SECRET
CADDY_ENCRYPTION_KEY=$CADDY_ENCRYPTION_KEY
CADDY_LDAP_BIND_USERNAME=$CADDY_LDAP_BIND_USERNAME
CADDY_LDAP_BIND_PASSWORD=$CADDY_LDAP_BIND_PASSWORD
EOF

echo "Setup completed successfully!"
echo ""
echo "LLDAP Admin Credentials:"
echo "- username: admin"
echo "- password: $LLDAP_ADMIN_PASSWORD"
echo ""
echo "To start the auth system:"
echo "1. Copy your TLS certificates:"
echo "   cp /etc/letsencrypt/live/$BASE_DOMAIN/fullchain.pem ./certs/cert.pem"
echo "   cp /etc/letsencrypt/live/$BASE_DOMAIN/privkey.pem ./certs/key.pem"
echo ""
echo "2. Start the services:"
echo "   docker-compose up -d"
echo ""
echo "Access points:"
echo "- Authentication portal: https://auth.$BASE_DOMAIN"
echo "- LLDAP admin: https://users.$BASE_DOMAIN"
echo ""
echo "Security notes:"
echo "- The LLDAP admin interface requires authentication"
echo "- TLS 1.3 and 1.2 are enforced for all connections"
echo "- Strong security headers are applied to all sites"
echo ""
echo "To integrate with Okta later, you'll need to configure an OpenID Connect provider in the Caddyfile"
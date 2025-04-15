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

AUTHELIA_JWT_SECRET=$(openssl rand -hex 16)
AUTHELIA_SESSION_SECRET=$(openssl rand -hex 16)
AUTHELIA_STORAGE_KEY=$(openssl rand -hex 16)
AUTHELIA_OIDC_HMAC_SECRET=$(openssl rand -hex 16)
OIDC_CLIENT_SECRET=$(openssl rand -hex 8)

# Generate .env file
cat > .env << EOF
# Domain Configuration
BASE_DOMAIN=$BASE_DOMAIN

# LLDAP Configuration
LLDAP_ADMIN_PASSWORD=$LLDAP_ADMIN_PASSWORD
LLDAP_JWT_SECRET=$LLDAP_JWT_SECRET
LLDAP_BASE_DN=$LLDAP_BASE_DN
LLDAP_AUTH_PASSWORD=$LLDAP_AUTH_PASSWORD

# Authelia Configuration
AUTHELIA_JWT_SECRET=$AUTHELIA_JWT_SECRET
AUTHELIA_SESSION_SECRET=$AUTHELIA_SESSION_SECRET
AUTHELIA_STORAGE_ENCRYPTION_KEY=$AUTHELIA_STORAGE_KEY
AUTHELIA_OIDC_HMAC_SECRET=$AUTHELIA_OIDC_HMAC_SECRET
OIDC_CLIENT_SECRET=$OIDC_CLIENT_SECRET
SMTP_PASSWORD=disabled
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
echo "- Authelia portal: https://auth.$BASE_DOMAIN"
echo "- LLDAP admin: https://users.$BASE_DOMAIN"
echo ""
echo "Security notes:"
echo "- The LLDAP admin interface requires two-factor authentication"
echo "- TLS 1.3 and 1.2 are enforced for all connections"
echo "- Strong security headers are applied to all sites"
echo ""
echo "Remember to set up email notifications for password resets by updating SMTP settings in authelia.yaml and .env"
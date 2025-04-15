#!/bin/bash

# Generate secrets for auth quickstart
echo "Generating auth quickstart configuration..."

# Prompt for Base Domain
read -p "Base Domain (e.g., example.com): " BASE_DOMAIN
if [ -z "$BASE_DOMAIN" ]; then
  echo "Base domain is required. Exiting."
  exit 1
fi

# Prompt for LLDAP Admin Password or generate a strong one
read -p "Enter LLDAP Admin Password (leave blank for random, secure password): " LLDAP_ADMIN_PASSWORD
if [ -z "$LLDAP_ADMIN_PASSWORD" ]; then
  # Generate a strong password (24 characters) with improved randomness
  LLDAP_ADMIN_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom | head -c 24)
fi


# Create .env file with generated secrets
# Start with a clean .env file
cat > .env << EOF
# LLDAP Configuration ----------------------------------
LLDAP_ADMIN_PASSWORD="$LLDAP_ADMIN_PASSWORD"
LLDAP_JWT_SECRET="$(openssl rand -hex 32)"
LLDAP_BASE_DN="$(echo $BASE_DOMAIN | sed 's/\./,dc=/g' | sed 's/^/dc=/')"
LLDAP_AUTH_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom | head -c 24)"

# Authelia Configuration ----------------------------------
AUTHELIA_JWT_SECRET="$(openssl rand -hex 32)"
AUTHELIA_SESSION_SECRET="$(openssl rand -hex 32)"
AUTHELIA_STORAGE_ENCRYPTION_KEY="$(openssl rand -hex 32)"
AUTHELIA_OIDC_HMAC_SECRET="$(openssl rand -hex 32)"
OIDC_CLIENT_SECRET="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom | head -c 24)"
SMTP_PASSWORD="disabled"

# General Configuration ----------------------------------
BASE_DOMAIN="$BASE_DOMAIN"
EOF


# Generate OIDC private key
openssl genrsa -out authelia/secrets/oidc_private_key.pem 4096
chmod 600 authelia/secrets/oidc_private_key.pem

# Set correct permissions for directories
chmod 750 authelia/secrets
chmod 750 certs

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
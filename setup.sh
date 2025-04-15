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

# Create required directories
mkdir -p authelia/config/secrets
mkdir -p config
mkdir -p certs

# Create .env file with generated secrets
echo "BASE_DOMAIN=$BASE_DOMAIN" > .env

# LLDAP Configuration
echo "LLDAP_ADMIN_PASSWORD=$LLDAP_ADMIN_PASSWORD" >> .env
echo "LLDAP_JWT_SECRET=$(openssl rand -hex 32)" >> .env
echo "LLDAP_BASE_DN=$(echo $BASE_DOMAIN | sed 's/\./,dc=/g' | sed 's/^/dc=/')" >> .env
echo "LLDAP_AUTH_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom | head -c 24)" >> .env

# Authelia Configuration
echo "AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)" >> .env
echo "AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)" >> .env
echo "AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)" >> .env
echo "AUTHELIA_OIDC_HMAC_SECRET=$(openssl rand -hex 32)" >> .env
echo "OIDC_CLIENT_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom | head -c 24)" >> .env

# Set default SMTP password to disabled for initial setup
echo "SMTP_PASSWORD=disabled" >> .env

# Generate OIDC private key
openssl genrsa -out authelia/config/secrets/oidc_private_key.pem 4096
chmod 600 authelia/config/secrets/oidc_private_key.pem

# Set correct permissions for directories
chmod 750 authelia/config/secrets
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
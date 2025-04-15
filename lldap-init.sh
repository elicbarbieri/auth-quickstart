#!/bin/sh

# Wait for LLDAP to be ready
echo "Waiting for LLDAP to be ready..."
until curl -s http://lldap:17170/api/health > /dev/null; do
  sleep 2
done

echo "LLDAP is ready, initializing users..."

# Login as admin to get token
TOKEN=$(curl -s -X POST http://lldap:17170/api/auth/simple \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$LLDAP_ADMIN_PASSWORD\"}" \
  | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Failed to authenticate with LLDAP"
  exit 1
fi

# Create authelia user
curl -s -X POST http://lldap:17170/api/user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"uid\": \"authelia\",
    \"display_name\": \"Authelia Service Account\",
    \"email\": \"authelia@$BASE_DOMAIN\",
    \"password\": \"$LLDAP_AUTH_PASSWORD\"
  }" > /dev/null

echo "Successfully created authelia user"

echo "LLDAP initialization completed successfully"
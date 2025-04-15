#!/bin/sh

# Wait for LLDAP to be ready
echo "Waiting for LLDAP to be ready..."
until curl -s http://lldap:17170/api/health > /dev/null; do
  sleep 2
done

# Add a longer wait to ensure LLDAP is fully initialized
sleep 5
echo "LLDAP is ready, initializing users..."

# Login as admin to get token
RESPONSE=$(curl -s -X POST http://lldap:17170/api/auth/simple \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$LLDAP_ADMIN_PASSWORD\"}")

echo "Authentication response: $RESPONSE"
TOKEN=$(echo "$RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "Failed to authenticate with LLDAP"
  exit 1
fi

echo "Successfully authenticated with LLDAP"

# Create Caddy auth user for LDAP binding
echo "Creating Caddy auth service account..."
CREATE_RESPONSE=$(curl -s -X POST http://lldap:17170/api/user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer \$TOKEN" \
  -d "{
    \"uid\": \"caddy-auth\",
    \"display_name\": \"Caddy Security Service Account\",
    \"email\": \"caddy-auth@$BASE_DOMAIN\",
    \"password\": \"$CADDY_LDAP_BIND_PASSWORD\"
  }")

echo "User creation response: \$CREATE_RESPONSE"

# Check if we got a success response
if echo "$CREATE_RESPONSE" | grep -q "user_id"; then
  echo "Successfully created Caddy auth user"
else
  echo "Failed to create Caddy auth user"
  # Don't exit with error here, as the user might already exist
fi

echo "LLDAP initialization completed successfully"
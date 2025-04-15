#!/bin/sh

# Wait for LLDAP to be ready
echo "Waiting for LLDAP to be ready..."
until curl -s http://lldap:17170/api/health > /dev/null; do
  sleep 2
done

# Add a longer wait to ensure LLDAP is fully initialized
sleep 5
echo "LLDAP is ready, initializing users..."

# Login as admin to get token - with debugging
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

# Create authelia user
echo "Creating authelia service account..."
CREATE_RESPONSE=$(curl -s -X POST http://lldap:17170/api/user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"uid\": \"authelia\",
    \"display_name\": \"Authelia Service Account\",
    \"email\": \"authelia@$BASE_DOMAIN\",
    \"password\": \"$LLDAP_AUTH_PASSWORD\"
  }")

echo "User creation response: $CREATE_RESPONSE"

# Check if we got a success response
if echo "$CREATE_RESPONSE" | grep -q "user_id"; then
  echo "Successfully created authelia user"
else
  echo "Failed to create authelia user"
  # Don't exit with error here, as the user might already exist
fi

echo "LLDAP initialization completed successfully"
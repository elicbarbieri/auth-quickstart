#!/bin/sh

# Wait for LLDAP to be ready
echo "Waiting for LLDAP to be ready..."

# Wait until the LLDAP health endpoint returns a non-HTML response
# or until maximum retry count is reached
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  HEALTH_RESPONSE=$(curl -s http://lldap:17170/api/health)
  # Check if response contains HTML (suggesting the UI is responding but API isn't ready)
  if ! echo "$HEALTH_RESPONSE" | grep -q "<!doctype html>"; then
    echo "LLDAP API is ready"
    break
  fi

  echo "Waiting for LLDAP API to initialize (attempt $RETRY_COUNT of $MAX_RETRIES)..."
  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "Timed out waiting for LLDAP API to initialize properly"
  echo "LLDAP may still be initializing its database. Will try to continue anyway."
fi

# Add a longer wait to ensure LLDAP is fully initialized
sleep 10
echo "LLDAP is ready, initializing users..."

# Debug LLDAP configuration
echo "Debugging LLDAP configuration:"
echo "  LLDAP admin password length: ${#LLDAP_ADMIN_PASSWORD}"
echo "  BASE_DOMAIN: $BASE_DOMAIN"

# Try authentication and handle potential HTML response
echo "Attempting to authenticate with LLDAP..."
AUTH_RESPONSE=$(curl -s -X POST http://lldap:17170/api/auth/simple \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$LLDAP_ADMIN_PASSWORD\"}")

# Check if response is HTML and extract token anyway
if echo "$AUTH_RESPONSE" | grep -q "<!doctype html>"; then
  echo "Received HTML response instead of JSON. LLDAP API may not be fully initialized."
  echo "Trying direct connection..."

  # Try an approach with basic auth header
  AUTH_RESPONSE=$(curl -s -X POST http://lldap:17170/api/auth/simple \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic $(echo -n "admin:$LLDAP_ADMIN_PASSWORD" | base64)" \
    -d "{}")
fi

echo "Authentication response: $AUTH_RESPONSE"
TOKEN=$(echo "$AUTH_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "Failed to authenticate with LLDAP"

  # Try to extract token from the HTML response (if it contains embedded JSON)
  JSON_IN_HTML=$(echo "$AUTH_RESPONSE" | grep -o '{.*}')
  if [ ! -z "$JSON_IN_HTML" ]; then
    TOKEN=$(echo "$JSON_IN_HTML" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [ ! -z "$TOKEN" ]; then
      echo "Found token in HTML response"
    fi
  fi

  # If still no token, exit
  if [ -z "$TOKEN" ]; then
    echo "Could not extract token from response. Exiting."
    exit 1
  fi
fi

echo "Successfully authenticated with LLDAP"

# Create Caddy auth user for LDAP binding
echo "Creating Caddy auth service account..."
CREATE_RESPONSE=$(curl -s -X POST http://lldap:17170/api/user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"uid\": \"caddy-auth\",
    \"display_name\": \"Caddy Security Service Account\",
    \"email\": \"caddy-auth@$BASE_DOMAIN\",
    \"password\": \"$CADDY_LDAP_BIND_PASSWORD\"
  }")

echo "User creation response: $CREATE_RESPONSE"

# Check if we got a success response
if echo "$CREATE_RESPONSE" | grep -q "user_id"; then
  echo "Successfully created Caddy auth user"
else
  echo "Failed to create Caddy auth user"
  echo "This may be normal if the user already exists"
fi

# Create a dedicated readonly group for service accounts if it doesn't exist
echo "Creating service account groups..."
GROUP_RESPONSE=$(curl -s -X POST http://lldap:17170/api/group \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"display_name\": \"Service Accounts\",
    \"description\": \"Group for service accounts with limited permissions\"
  }")

echo "Group creation response: $GROUP_RESPONSE"

# Add the caddy-auth user to the service group
echo "Adding caddy-auth user to service group..."
ADD_GROUP_RESPONSE=$(curl -s -X PUT http://lldap:17170/api/user/caddy-auth/groups \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "[\"Service Accounts\"]")

echo "Add to group response: $ADD_GROUP_RESPONSE"

echo "LLDAP initialization completed successfully"
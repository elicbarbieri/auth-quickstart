import requests
import os
import time
import json
import secrets
import string

# Configuration from environment
AUTHENTIK_URL = os.environ.get('AUTHENTIK_URL')
AUTHENTIK_ADMIN_USER = os.environ.get('AUTHENTIK_ADMIN_USER')
AUTHENTIK_ADMIN_PASSWORD = os.environ.get('AUTHENTIK_ADMIN_PASSWORD')
BASE_DOMAIN = os.environ.get('BASE_DOMAIN')
CADDY_CONFIG_PATH = os.environ.get('CADDY_CONFIG_PATH')

# Generate a secure random string
def generate_secret(length=32):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))

# Wait for Authentik to be ready
def wait_for_authentik():
    print("Waiting for Authentik to be ready...")
    retry_count = 0
    max_retries = 30

    while retry_count < max_retries:
        try:
            response = requests.get(f"{AUTHENTIK_URL}/api/v3/core/applications/")
            if response.status_code < 500:  # Accept even 4xx as Authentik might be up but require auth
                print("Authentik is ready")
                return True
        except requests.RequestException:
            pass

        retry_count += 1
        print(f"Retry {retry_count}/{max_retries}...")
        time.sleep(10)

    print("Timed out waiting for Authentik")
    return False

# Create a service account and token for API access
def create_service_account_and_token():
    print("Creating a service account and token...")

    # Step 1: Login to get a session cookie
    session = requests.Session()
    login_url = f"{AUTHENTIK_URL}/api/v3/core/auth/flows/"

    login_data = {
        "flow": "default-authentication-flow",
        "component": "ak-stage-identification",
        "data": {
            "username": AUTHENTIK_ADMIN_USER,
            "password": AUTHENTIK_ADMIN_PASSWORD
        }
    }

    headers = {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
    }

    try:
        response = session.post(login_url, json=login_data, headers=headers)
        if response.status_code != 200:
            print(f"Login failed: {response.status_code} - {response.text}")
            return None

        # Step 2: Create a service account user
        service_account_name = f"init-service-{int(time.time())}"
        user_url = f"{AUTHENTIK_URL}/api/v3/core/users/"

        user_data = {
            "username": service_account_name,
            "name": f"Initial Setup Service Account",
            "path": "service-accounts",
            "groups": [],
            "is_active": True,
            "attributes": {
                "service_account": True
            }
        }

        user_response = session.post(user_url, json=user_data)
        if user_response.status_code > 299:
            print(f"Service account creation failed: {user_response.status_code} - {user_response.text}")
            return None

        user_id = user_response.json()['pk']

        # Step 3: Create a token for this service account
        token_url = f"{AUTHENTIK_URL}/api/v3/core/tokens/"
        token_identifier = generate_secret(12)

        token_data = {
            "identifier": f"init-token-{token_identifier}",
            "user": user_id,
            "intent": "api",
            "expiring": False,
            "description": "Initial setup token"
        }

        token_response = session.post(token_url, json=token_data)
        if token_response.status_code > 299:
            print(f"Token creation failed: {token_response.status_code} - {token_response.text}")
            return None

        # The key value in the response is the token we need
        token_key = token_response.json().get('key')
        print(f"Successfully created service account and token")
        return {
            "token": token_key,
            "user_id": user_id
        }

    except Exception as e:
        print(f"Error in service account creation: {str(e)}")
        return None

# Create Forward Auth provider
def create_proxy_provider(token):
    provider_url = f"{AUTHENTIK_URL}/api/v3/providers/proxy/"

    # First create an application
    app_url = f"{AUTHENTIK_URL}/api/v3/core/applications/"
    app_payload = {
        "name": "Caddy Forward Auth",
        "slug": "caddy-forward-auth",
        "provider": None,
        "meta_launch_url": "",
        "policy_engine_mode": "all",
        "group": None
    }

    print("Creating application...")
    app_response = requests.post(
        app_url,
        json=app_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    if app_response.status_code > 299:
        print(f"App creation failed: {app_response.text}")
        return None

    app_id = app_response.json()['pk']

    # Now create the Proxy provider for forward auth
    provider_payload = {
        "name": "Caddy Forward Auth Provider",
        "authorization_flow": "default-provider-authorization-implicit-consent",
        "authentication_flow": "default-authentication-flow",
        "internal_host": "http://authentik-server:9000",
        "external_host": f"https://auth.{BASE_DOMAIN}",
        "mode": "forward_single",
        "application": app_id
    }

    print("Creating provider...")
    provider_response = requests.post(
        provider_url,
        json=provider_payload,
        headers={"Authorization": f"Bearer {token}"}
    )

    if provider_response.status_code > 299:
        print(f"Provider creation failed: {provider_response.text}")
        return None

    provider_data = provider_response.json()
    return {
        "provider_id": provider_data["pk"],
        "application_id": app_id
    }

# Get the embedded outpost and update it to include the new application
def update_embedded_outpost(token, app_id):
    print("Updating embedded outpost...")

    # Get list of outposts to find the embedded one
    outposts_url = f"{AUTHENTIK_URL}/api/v3/outposts/"
    outposts_response = requests.get(
        outposts_url,
        headers={"Authorization": f"Bearer {token}"}
    )

    if outposts_response.status_code > 299:
        print(f"Failed to get outposts: {outposts_response.text}")
        return False

    outposts = outposts_response.json().get('results', [])
    embedded_outpost = None

    # Find the embedded outpost
    for outpost in outposts:
        if outpost.get('type') == 'authentik_outposts.embedded':
            embedded_outpost = outpost
            break

    if not embedded_outpost:
        print("Embedded outpost not found")
        return False

    # Get current applications and add the new one
    outpost_id = embedded_outpost['pk']
    current_apps = embedded_outpost.get('applications', [])

    # Check if app is already in the list
    if app_id not in current_apps:
        current_apps.append(app_id)

    # Update outpost with new application list
    update_url = f"{AUTHENTIK_URL}/api/v3/outposts/{outpost_id}/"
    update_data = {
        "applications": current_apps,
        "name": embedded_outpost['name']  # Name is required for update
    }

    update_response = requests.patch(
        update_url,
        json=update_data,
        headers={"Authorization": f"Bearer {token}"}
    )

    if update_response.status_code > 299:
        print(f"Failed to update outpost: {update_response.text}")
        return False

    print(f"Successfully updated embedded outpost to include new application")
    return True

# Save configuration for Caddy
def save_caddy_config(provider_config):
    os.makedirs(CADDY_CONFIG_PATH, exist_ok=True)

    config_file = os.path.join(CADDY_CONFIG_PATH, "auth_config.json")
    config = {
        "provider_id": provider_config["provider_id"],
        "application_id": provider_config["application_id"],
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S")
    }

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    print(f"Saved configuration to {config_file}")

# Main function
def main():
    try:
        # Wait for Authentik to be ready
        if not wait_for_authentik():
            return

        # Wait a bit more to ensure flows are initialized
        time.sleep(5)

        # Create a service account for token generation
        service_account_data = create_service_account_and_token()

        if not service_account_data:
            print("Failed to create service account - please check your configuration")
            return

        token = service_account_data["token"]
        print("Authentication successful")

        # Create Proxy provider
        provider_config = create_proxy_provider(token)
        if not provider_config:
            print("Failed to create provider")
            return

        print(f"Created Proxy provider with ID: {provider_config['provider_id']}")

        # Update embedded outpost to include the new application
        outpost_updated = update_embedded_outpost(token, provider_config['application_id'])
        if not outpost_updated:
            print("Warning: Failed to update embedded outpost, forward auth may not work properly")

        # Save configuration
        save_caddy_config(provider_config)

        print("Initialization completed successfully")

    except Exception as e:
        print(f"Error: {str(e)}")
        raise

if __name__ == "__main__":
    main()
import requests
import os
import time
import json
import secrets
import string

# Configuration from environment
AUTHENTIK_URL = os.environ.get('AUTHENTIK_URL')
AUTHENTIK_ADMIN_USER = os.environ.get('AUTHENTIK_ADMIN_USER')
AUTHENTIK_BOOTSTRAP_TOKEN = os.environ.get('AUTHENTIK_BOOTSTRAP_TOKEN')
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

# Use the bootstrap token for API authentication
def get_api_token():
    # Check if AUTHENTIK_BOOTSTRAP_TOKEN is available
    if not AUTHENTIK_BOOTSTRAP_TOKEN:
        print("Error: AUTHENTIK_BOOTSTRAP_TOKEN environment variable is not set.")
        print("Please add AUTHENTIK_BOOTSTRAP_TOKEN to both server and worker containers.")
        return None

    print("Using AUTHENTIK_BOOTSTRAP_TOKEN for API authentication")
    return AUTHENTIK_BOOTSTRAP_TOKEN

# Create Forward Auth provider
def create_proxy_provider(token):
    provider_url = f"{AUTHENTIK_URL}/api/v3/providers/proxy/"

    # First we need to get a valid group to use
    groups_url = f"{AUTHENTIK_URL}/api/v3/core/groups/"
    print("Fetching available groups...")

    groups_response = requests.get(
        groups_url,
        headers={"Authorization": f"Bearer {token}"}
    )

    if groups_response.status_code != 200:
        print(f"Failed to fetch groups: {groups_response.text}")
        return None

    groups_data = groups_response.json()
    if not groups_data.get('results') or len(groups_data['results']) == 0:
        print("No groups found in Authentik")
        return None

    # Use the first available group (typically "authentik Admins")
    default_group = groups_data['results'][0]['pk']
    print(f"Using group: {groups_data['results'][0]['name']} (ID: {default_group})")

    # Create an application
    app_url = f"{AUTHENTIK_URL}/api/v3/core/applications/"
    app_payload = {
        "name": "Caddy Forward Auth",
        "slug": "caddy-forward-auth",
        "provider": None,
        "meta_launch_url": "",
        "policy_engine_mode": "all",
        "group": default_group
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

    # Now create the Proxy provider for domain-level authentication
    provider_payload = {
        "name": "Caddy Forward Auth Provider",
        "authorization_flow": "default-provider-authorization-implicit-consent",
        "authentication_flow": "default-authentication-flow",
        "internal_host": "http://authentik-server:9000",
        "external_host": f"https://auth.{BASE_DOMAIN}",
        "mode": "forward_domain",
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

# We no longer need this alternative method since we're using the bootstrap token
# that's set via environment variables on startup

# Main function
def main():
    try:
        # Wait for Authentik to be ready
        if not wait_for_authentik():
            return

        # Wait a bit more to ensure flows are initialized
        time.sleep(5)

        # Get the bootstrap token
        token = get_api_token()

        if not token:
            print("Authentication failed - Make sure the AUTHENTIK_BOOTSTRAP_TOKEN environment variable is set")
            print("Add it to both authentik-server and authentik-worker containers in docker-compose.yaml")
            return

        print("Authentication successful using bootstrap token")

        # Create Proxy provider
        provider_config = create_proxy_provider(token)
        if not provider_config:
            print("Failed to create provider")
            return

        print(f"Created Proxy provider with ID: {provider_config['provider_id']}")

        # Save configuration
        save_caddy_config(provider_config)

        print("Initialization completed successfully")

    except Exception as e:
        print(f"Error: {str(e)}")
        raise

if __name__ == "__main__":
    main()
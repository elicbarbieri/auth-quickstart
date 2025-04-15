import requests
import os
import time
import json
import secrets
import string
import sys

# Configuration from environment
AUTHENTIK_URL = os.environ.get('AUTHENTIK_URL')
AUTHENTIK_ADMIN_USER = os.environ.get('AUTHENTIK_ADMIN_USER')
AUTHENTIK_BOOTSTRAP_TOKEN = os.environ.get('AUTHENTIK_BOOTSTRAP_TOKEN')
BASE_DOMAIN = os.environ.get('BASE_DOMAIN')
CADDY_CONFIG_PATH = os.environ.get('CADDY_CONFIG_PATH')

if not all([AUTHENTIK_URL, BASE_DOMAIN, CADDY_CONFIG_PATH]):
    print("Error: AUTHENTIK_URL, BASE_DOMAIN, and CADDY_CONFIG_PATH environment variables must be set.")
    sys.exit(1)

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
        sys.exit(1)

    print("Using AUTHENTIK_BOOTSTRAP_TOKEN for API authentication")
    return AUTHENTIK_BOOTSTRAP_TOKEN

# Create Forward Auth provider
def create_proxy_provider(token):
    provider_url = f"{AUTHENTIK_URL}/api/v3/providers/proxy/"
    app_slug = "caddy-forward-auth"
    app_name = "Caddy Forward Auth"
    app_url = f"{AUTHENTIK_URL}/api/v3/core/applications/"

    # First we need to get a valid group to use
    groups_url = f"{AUTHENTIK_URL}/api/v3/core/groups/"
    print("Fetching available groups...")

    try:
        groups_response = requests.get(
            groups_url,
            headers={"Authorization": f"Bearer {token}"}
        )
        groups_response.raise_for_status()  # Raise an exception for bad status codes
        groups_data = groups_response.json()
        if not groups_data.get('results') or len(groups_data['results']) == 0:
            print("Error: No groups found in Authentik.")
            sys.exit(1)

        # Use the first available group (typically "authentik Admins")
        default_group_id = groups_data['results'][0]['pk']
        default_group_name = groups_data['results'][0]['name']
        print(f"Using group: {default_group_name} (ID: {default_group_id})")

    except requests.exceptions.RequestException as e:
        print(f"Error fetching groups: {e}")
        sys.exit(1)

    # Check if the application already exists
    try:
        existing_apps_response = requests.get(
            f"{app_url}?slug={app_slug}",
            headers={"Authorization": f"Bearer {token}"}
        )
        existing_apps_response.raise_for_status()
        existing_apps = existing_apps_response.json()
        app_id = None

        # If the application already exists, use it
        if existing_apps.get('count', 0) > 0:
            app_id = existing_apps['results'][0]['pk']
            print(f"Application with slug '{app_slug}' already exists (ID: {app_id}).")
        else:
            # Create a new application
            app_payload = {
                "name": app_name,
                "slug": app_slug,
                "provider": None,
                "meta_launch_url": "",
                "policy_engine_mode": "all",
                "group": default_group_id
            }

            print("Creating application...")
            app_response = requests.post(
                app_url,
                json=app_payload,
                headers={"Authorization": f"Bearer {token}"}
            )
            app_response.raise_for_status()
            app_id = app_response.json()['pk']
            print(f"Created new application '{app_name}' with ID: {app_id}")

    except requests.exceptions.RequestException as e:
        print(f"Error checking or creating application: {e}")
        sys.exit(1)

    if not app_id:
        print("Error: Could not determine application ID.")
        sys.exit(1)

    # Check if a proxy provider for this application already exists
    try:
        providers_response = requests.get(
            f"{provider_url}?application={app_id}",
            headers={"Authorization": f"Bearer {token}"}
        )
        providers_response.raise_for_status()
        providers = providers_response.json()
        provider_id = None

        # If a provider exists for this application, use it
        if providers.get('count', 0) > 0:
            provider_id = providers['results'][0]['pk']
            print(f"Provider already exists (ID: {provider_id}) for application '{app_name}'.")
            return {
                "provider_id": provider_id,
                "application_id": app_id
            }
        else:
            # Create a new proxy provider for domain-level authentication
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
            provider_response.raise_for_status()
            provider_data = provider_response.json()
            print(f"Created Proxy provider with ID: {provider_data['pk']} for application '{app_name}'.")
            return {
                "provider_id": provider_data["pk"],
                "application_id": app_id
            }

    except requests.exceptions.RequestException as e:
        print(f"Error checking or creating provider: {e}")
        sys.exit(1)

    return None # Should not reach here if provider creation was successful or existed

# Save configuration for Caddy
def save_caddy_config(provider_config):
    os.makedirs(CADDY_CONFIG_PATH, exist_ok=True)

    config_file = os.path.join(CADDY_CONFIG_PATH, "auth_config.json")
    config = {
        "provider_id": provider_config["provider_id"],
        "application_id": provider_config["application_id"],
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S")
    }

    try:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        print(f"Saved configuration to {config_file}")
    except IOError as e:
        print(f"Error saving Caddy configuration: {e}")
        sys.exit(1)


# Main function
def main():
    try:
        # Wait for Authentik to be ready
        if not wait_for_authentik():
            sys.exit(1)

        # Wait a bit more to ensure flows are initialized
        time.sleep(5)

        # Get the bootstrap token
        token = get_api_token()

        if not token:
            print("Authentication failed - Make sure the AUTHENTIK_BOOTSTRAP_TOKEN environment variable is set")
            print("Add it to both authentik-server and authentik-worker containers in docker-compose.yaml")
            sys.exit(1)

        print("Authentication successful using bootstrap token")

        # Create Proxy provider
        provider_config = create_proxy_provider(token)
        if not provider_config:
            print("Failed to configure provider. Check logs for details.")
            sys.exit(1)

        print(f"Provider configuration successful (Provider ID: {provider_config['provider_id']}, Application ID: {provider_config['application_id']})")

        # Save configuration
        save_caddy_config(provider_config)

        print("Initialization completed successfully")
        sys.exit(0)

    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
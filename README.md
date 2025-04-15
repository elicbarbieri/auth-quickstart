# Secure Auth Quickstart

A secure and very fast way to add authentication to any Docker application stack. This repo provides a complete, 
staging-ready authentication system using LLDAP, Authelia, and Caddy.

If you want to go crazy and run this in production....  go for it you crazy bastard.

That said, this is a very simple and easy to use authentication system perfect for testing an app with its 
first thousand users, or really quickly getting an internal app up and running securely.

## Security Invariants

This is a list of things you MUST do in order to securely use this system:
- SSH keypair with strong passphrase, or username + good password
- No other users able to access the server & no weird shit installed
- Don't store cryptographic information in stupid places.  SSL certificates belong on the server, not your notes app
- Don't delete the .env file, the JWT secrets and auth keys are annoying to re-generate
- Turn on a firewall


## Features

- **Complete Authentication System**: User management, SSO, MFA, and OIDC support
- **Simple Setup**: Takes 5 minutes to deploy
- **Secure by Default**: Modern security standards and best practices
- **Easy Integration**: Works with any HTTP services
- **Zero Click-Ops**: No clicking through auth dashboards to get it running

## Prerequisites
- application stack based on docker or docker-compose  
- Wildcard DNS record, i.e., `*.example.com` → your server IP
- TLS Certificate for `*.example.com` (create using Let's Encrypt & DNS challenge)

## Creating TLS Certificates with Let's Encrypt

```bash
# Install certbot
sudo apt-get install certbot python3-certbot

# Generate a wildcard certificate using DNS validation
certbot certonly --manual --preferred-challenges dns -d *.example.com -d example.com
```

## Setup

```bash
# Clone the repository
git clone https://github.com/elicbarbieri/auth-quickstart.git
cd auth-quickstart

# Run the setup script
./setup.sh

# Copy your TLS certificates
cp /etc/letsencrypt/live/example.com/fullchain.pem ./certs/cert.pem
cp /etc/letsencrypt/live/example.com/privkey.pem ./certs/key.pem

# Start the services
docker-compose up -d
```

## Adding Firewall to server
```bash
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw enable
```

## Accessing Your Services

- **Authelia Portal**: `https://auth.example.com`
- **LLDAP Admin**: `https://users.example.com`

## Adding Your Applications

To protect your own applications with this authentication system:

### 1: Expose ports in your apps docker-compose.yaml
Go to the docker-compose.yaml file of your application stack and add/change the open ports for the services
you want to protect.

> **Warning:** DO NOT add ports without the 127.0.0.1 prefix!!! By adding the prefix, docker restricts external traffic on those ports "

```yaml
ports:
- "127.0.0.1:8080:8080"
```
2. Configure Caddy to proxy to your application (example in Caddyfile)

Example Caddyfile entry:

```caddy
app.example.com {
    import security_headers
    tls /certs/cert.pem /certs/key.pem {
        protocols tls1.3 tls1.2
    }
    forward_auth authelia:9091 {
        uri /api/verify?rd=https://auth.example.com
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
    reverse_proxy host.docker.internal:8080
}
```

## Security Features

- **Two-factor authentication** support via Authelia
- **Single Sign-On** for all your applications
- **Security headers** on all protected sites

## Troubleshooting

If you encounter any issues:

- Check Docker container logs: `docker logs authelia`
- Verify network connectivity between containers
- Confirm DNS resolution works correctly
- Ensure TLS certificates are valid

## License

MIT
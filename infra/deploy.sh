#!/bin/bash

CONFIG_FILE="/etc/pyron/configure-server"

# Function to check if script should run
should_run() {
    if [ -f "$CONFIG_FILE" ] && grep -q "first-run=true" "$CONFIG_FILE"; then
        return 0
    fi
    # Allow manual re-run if argument is provided
    if [ "$1" == "--force" ]; then
        return 0
    fi
    # Check if we are in a "self-signed" state but want "real certs"
    if [ -n "$HOSTNAME" ] && [ -f "/etc/nginx/ssl/selfsigned.crt" ]; then
        echo "Hostname set but using self-signed certs. Checking if we can upgrade..."
        return 0
    fi
    return 1
}

echo "Starting deployment script..."

# Always ensure packages are installed (idempotent)
echo "Updating packages..."
apt update -y && apt upgrade -y
apt install -y docker.io nginx certbot python3-certbot-nginx dnsutils

echo "Enabling services..."
systemctl enable --now docker
systemctl enable --now nginx

# Create deployment directory
mkdir -p /root/pyron-app

echo "Configuring nginx..."
# Fix: Correct path for sites-available
rm -f /etc/nginx/sites-available/default
rm -f /etc/nginx/sites-enabled/default

# Generate dhparam.pem if it doesn't exist (needed for both modes)
if [ ! -f /etc/nginx/dhparam.pem ]; then
    echo "Generating dhparam.pem..."
    openssl dhparam -out /etc/nginx/dhparam.pem 2048
fi

# Get Public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
echo "Public IP: $PUBLIC_IP"

DOMAIN_RESOLVES=false

if [ -n "$HOSTNAME" ]; then
    echo "HOSTNAME is set to $HOSTNAME."
    RESOLVED_IP=$(dig +short "$HOSTNAME" | tail -n1)
    echo "Resolved IP for $HOSTNAME: $RESOLVED_IP"
    
    if [ "$RESOLVED_IP" == "$PUBLIC_IP" ]; then
        echo "DNS matches Public IP. Proceeding with Certbot..."
        DOMAIN_RESOLVES=true
    else
        echo "WARNING: DNS ($RESOLVED_IP) does not match Public IP ($PUBLIC_IP). Falling back to Self-Signed Certificate."
    fi
fi

if [ "$DOMAIN_RESOLVES" = true ]; then
    echo "Configuring for domain $HOSTNAME..."
    
    NGINX_CONFIG="/etc/nginx/sites-available/$HOSTNAME"

    # 1. Configure HTTP only first to allow Certbot validation
    cat > "$NGINX_CONFIG" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $HOSTNAME;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "$NGINX_CONFIG" "/etc/nginx/sites-enabled/$HOSTNAME"
    # Remove default/self-signed config if it exists
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx

    # 2. Obtain SSL certificate
    echo "Obtaining SSL certificate with Certbot..."
    if certbot certonly --nginx -d "$HOSTNAME" --non-interactive --agree-tos -m admin@$HOSTNAME; then
        # 3. Write full hardened HTTPS config
        cat > "$NGINX_CONFIG" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444; 
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_reject_handshake on; 
}

server {
    listen 80;
    listen [::]:80;
    server_name $HOSTNAME;
    server_tokens off;
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $HOSTNAME;

    server_tokens off;

    ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    ssl_dhparam /etc/nginx/dhparam.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 1.0.0.1 valid=300s;
    resolver_timeout 5s;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy-Report-Only "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;" always;

    client_body_buffer_size 10K;
    client_header_buffer_size 1k;
    client_max_body_size 8m;
    large_client_header_buffers 2 1k;

    client_body_timeout 12;
    client_header_timeout 12;
    keepalive_timeout 15;
    send_timeout 10;

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # CRITICAL: Tell FastAPI we are using HTTPS
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        nginx -t && systemctl reload nginx
        
        # Cleanup self-signed if it exists
        rm -f /etc/nginx/sites-enabled/default
    else
        echo "Certbot failed. Keeping previous configuration."
    fi
else
    echo "Configuring for IP with self-signed certificate (Fallback)..."
    
    # Generate self-signed certificate
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/selfsigned.key \
        -out /etc/nginx/ssl/selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

    NGINX_CONFIG="/etc/nginx/sites-available/default"

    cat > "$NGINX_CONFIG" <<EOF
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    ssl_dhparam /etc/nginx/dhparam.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # No OCSP stapling for self-signed

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy-Report-Only "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;" always;

    client_body_buffer_size 10K;
    client_header_buffer_size 1k;
    client_max_body_size 8m;
    large_client_header_buffers 2 1k;

    client_body_timeout 12;
    client_header_timeout 12;
    keepalive_timeout 15;
    send_timeout 10;

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
fi

# Update config file to prevent re-execution
sed -i 's/first-run=true/first-run=false/' "$CONFIG_FILE"
echo "Configuration complete."
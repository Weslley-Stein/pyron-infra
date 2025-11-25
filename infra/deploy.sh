#!/bin/bash

CONFIG_FILE="/etc/pyron/configure-server"

if [ -f "$CONFIG_FILE" ] && grep -q "first-run=true" "$CONFIG_FILE"; then
    echo "First run detected. Configuring server..."

    echo "Updating packages..."
    apt update -y && apt upgrade -y

    echo "Enabling services..."
    systemctl enable --now docker
    systemctl enable --now nginx

    echo "Configuring nginx..."
    # Fix: Correct path for sites-available
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default

    # Generate dhparam.pem if it doesn't exist (needed for both modes)
    if [ ! -f /etc/nginx/dhparam.pem ]; then
        echo "Generating dhparam.pem..."
        openssl dhparam -out /etc/nginx/dhparam.pem 2048
    fi
    
    if [ -n "$HOSTNAME" ]; then
        echo "HOSTNAME is set to $HOSTNAME. Configuring for domain..."
        
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
        nginx -t && systemctl reload nginx

        # 2. Obtain SSL certificate
        echo "Obtaining SSL certificate with Certbot..."
        certbot certonly --nginx -d "$HOSTNAME" --non-interactive --agree-tos -m admin@$HOSTNAME

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
    else
        echo "HOSTNAME is not set. Configuring for IP with self-signed certificate..."
        
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
else
    echo "Not first run or config file missing. Skipping configuration."
fi
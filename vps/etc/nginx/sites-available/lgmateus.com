server {
    listen 80;
    listen [::]:80;
    server_name lgmateus.com www.lgmateus.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name lgmateus.com www.lgmateus.com;

    ssl_certificate     /etc/ssl/cloudflare/lgmateus.crt;
    ssl_certificate_key /etc/ssl/cloudflare/lgmateus.key;

    # Authenticated Origin Pulls — so aceita requests com o cert de cliente da Cloudflare
    # (cert global, ligado em SSL/TLS -> Origin Server -> Authenticated Origin Pulls).
    ssl_client_certificate /etc/ssl/cloudflare/authenticated_origin_pull_ca.pem;
    ssl_verify_client on;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

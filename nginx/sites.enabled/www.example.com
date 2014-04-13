map $http_host $magecode { 
  www.example.com default;
  www.example.fr fr;
  www.example.co.uk uk;
}

server {
  listen 81;
  server_name www.example.com www.example.fr www.example.co.uk;
  index index.php;
  root /home/www/www.example.com/;
  error_page   500 502 503 504 /50x.html;
  access_log /var/log/nginx/www.example.com_access.log;

  location / {
    index  index.php;
    if ($request_uri ~* ".*\.(swf|ico|css|js|gif|jpe?g|png)") {
        add_header Cache-Control max-age=315360000 ;
        break;
    }
    try_files $uri $uri/ @handler;
    expires 30d;
  }

  location @handler {
    rewrite / /index.php;
  }
    
  location /app/ { deny all; }
  location /includes/ { deny all; }
  location /lib/ { deny all; }
  location /media/downloadable/ { deny all; }

  location ~ ^/magmi/.*\.php {
    if ($remote_addr !~ "(127.0.0.1)") {
      return 403;
    }
    include /etc/nginx/nginx-fpm.conf;
  }

  rewrite ^/api/rest /api.php?type=rest break;

  rewrite ^/minify/([0-9]+)(/.*.(js|css))$ /lib/minify/m.php?f=$2&d=$1 last;
  rewrite ^/skin/m/([0-9]+)(/.*.(js|css))$ /lib/minify/m.php?f=$2&d=$1 last;

  location /lib/minify/ {
    allow all;
  }

  location ~ \.php$ {
    fastcgi_param MAGE_IS_DEVELOPER_MODE 0;
    fastcgi_param MAGE_RUN_TYPE website;
    fastcgi_param MAGE_RUN_CODE $magecode;
    include /etc/nginx/nginx-fpm.conf;
  }
}

server {
  listen 443;
  ssl on;
  ssl_certificate_key /etc/nginx/ssl/example.key ;
  ssl_certificate /etc/nginx/ssl/example.crt ;

  server_name www.example.com www.example.fr www.example.co.uk;
  index index.php;
  root /home/www/www.example.com/;
  error_page   500 502 503 504 /50x.html;
  access_log /var/log/nginx/www.example.com_access.log;

  location /api {
    rewrite ^/api/rest /api.php?type=rest last;
    rewrite ^/api/v2_soap /api.php?type=v2_soap last;
    rewrite ^/api/soap /api.php?type=soap last;
  }

  location / {
    index  index.php;
    if ($request_uri ~* ".*\.(swf|ico|css|js|gif|jpe?g|png)") {
        add_header Cache-Control max-age=315360000 ;
        break;
    }

    try_files $uri $uri/ @handler;
    expires 30d;
  }

  location @handler {
    rewrite / /index.php;
  }

  location /app/ { deny all; }
  location /includes/ { deny all; }
  location /lib/ { deny all; }
  location /media/downloadable/ { deny all; }

  location ~ ^/magmi/.*\.php {
    if ($remote_addr !~ "(127.0.0.1)") {
      return 403;
    }
    include /etc/nginx/nginx-fpm.conf;
  }

  rewrite ^/minify/([0-9]+)(/.*.(js|css))$ /lib/minify/m.php?f=$2&d=$1 last;
  rewrite ^/skin/m/([0-9]+)(/.*.(js|css))$ /lib/minify/m.php?f=$2&d=$1 last;

  location /lib/minify/ {
    allow all;
  }

  location ~ \.php$ {
    fastcgi_param MAGE_IS_DEVELOPER_MODE 0;
    fastcgi_param MAGE_RUN_TYPE website;
    fastcgi_param MAGE_RUN_CODE $magecode;
    include /etc/nginx/nginx-fpm.conf;
    fastcgi_param  HTTPS on;
  }
}



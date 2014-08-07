#!/bin/bash

echo "Setting up portal for $DIT4C_DOMAIN"
echo "SSL key & certificate should be in $SSL_DIR"
echo "All other config files should be in $CONFIG_DIR"

DOCKER_SOCKET="/var/run/docker.sock"

if [ !-S $DOCKER_SOCKET ]
then
    echo "Host Docker socket should be mounted at $DOCKER_SOCKET"
    exit 1
fi

docker run --name dit4c_ssl_keys -v $SSL_DIR:/etc/ssl busybox \
  "stat /etc/ssl/server.key && stat /etc/ssl/server.crt"

KEYS_EXIST=!$?

if [ !$KEYS_EXIST ]
then
    echo "Required keys are missing from $SSL_DIR"
    exit 1
fi

# Create DB servers
docker run --name dit4c_couchdb \
    -v /var/log/dit4c_couchdb:/var/log \
    -v /var/lib/couchdb \
    fedora/couchdb
docker run --name dit4c_redis \
    -v /var/log/dit4c_redis:/var/log \
    -v /var/lib/redis \
    fedora/redis

# Create highcommand and hipache servers
docker run --name dit4c_highcommand \
    -v /var/log/dit4c_highcommand:/var/log \
    -v $CONFIG_DIR/dit4c-highcommand.conf:/etc/dit4c-highcommand.conf
    --link dit4c_redis:redis \
    --link dit4c_couchdb:couchdb \
    dit4c/dit4c-platform-highcommand
docker run --name dit4c_hipache \
    --link dit4c_redis:redis \
    -v /var/log/dit4c_hipache:/var/log \
    dit4c/dit4c-platform-hipache

docker run --name dit4c_ssl \
    -p 80:80 -p 443:443 \
    -e DIT4C_DOMAIN=$DIT4C_DOMAIN \
    --volumes-from dit4c_ssl_keys:ro \
    --link dit4c_highcommand:dit4c-highcommand \
    --link dit4c_hipache:hipache \
    -v /var/log/dit4c_ssl:/var/log \
    dit4c/dit4c-platform-ssl








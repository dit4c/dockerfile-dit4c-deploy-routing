#!/bin/sh

set -e

echo "Setting up routing frontend for $DIT4C_DOMAIN"
echo "SSL key & certificate should be in $SSL_DIR"

DOCKER_SOCKET="/var/run/docker.sock"

if [ ! -S $DOCKER_SOCKET ]
then
    echo "Host Docker socket should be mounted at $DOCKER_SOCKET"
    exit 1
fi

docker start -ia dit4c_ssl_keys || docker run --name dit4c_ssl_keys \
  -v $SSL_DIR/server.key:/etc/ssl/server.key \
  -v $SSL_DIR/server.crt:/etc/ssl/server.crt \
  --restart=no \
  gentoobb/openssl sh -c \
  "openssl rsa -in /etc/ssl/server.key -modulus -noout > /tmp/key_modulus; \
   openssl x509 -modulus -in /etc/ssl/server.crt -noout > /tmp/cert_modulus; \
   diff /tmp/key_modulus /tmp/cert_modulus"

KEYS_EXIST=$?

if [ $KEYS_EXIST ]
then
    echo "Required key and certificate are present and match"
else
    echo "Required key or certificate are missing/invalid in $SSL_DIR"
    exit 1
fi

# Create SSL termination frontend
docker start dit4c_switchboard || docker run -d --name dit4c_switchboard \
    -p 443:8080 \
    -e DIT4C_DOMAIN=$DIT4C_DOMAIN \
    -e DIT4C_ROUTE_FEED=https://$DIT4C_DOMAIN/routes \
    -v $CONFIG_DIR:/etc/dit4c-switchboard.d:ro \
    --volumes-from dit4c_ssl_keys:ro \
    --restart=always \
    dit4c/dit4c-platform-switchboard

echo "Done configuring routing."

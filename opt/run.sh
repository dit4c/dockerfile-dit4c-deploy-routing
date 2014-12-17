#!/bin/bash

echo "Setting up portal for $DIT4C_DOMAIN"
echo "SSL key & certificate should be in $SSL_DIR"
echo "All other config files should be in $CONFIG_DIR"

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

# Create DB server
docker start dit4c_couchdb || docker run -d --name dit4c_couchdb \
    -v /usr/local/var/log/couchdb:/var/log \
    --restart=always \
    klaemo/couchdb

# Establish if we need a local etcd, or we can reuse the host etcd
curl -XHEAD -H "Connection: close" -v "http://172.17.42.1:4001/v2/stats/self"
if [[ $? == 0 ]]
then
  echo "Using host etcd"
  docker start dit4c_etcd || docker run -d --name dit4c_etcd \
      --restart=always \
      --expose 4001 -e ETCD_PORT_4001_TCP=tcp://172.17.42.1:4001 \
      svendowideit/ambassador
else
  echo "Using standalone etcd"
  docker start dit4c_etcd || docker run -d --name dit4c_etcd \
      -v /var/log/dit4c_etcd:/var/log \
      -v /var/lib/redis \
      --restart=always \
      coreos/etcd:v0.4.6
fi

# Wait a little to ensure dit4c_couchdb & dit4c_etcd exist
until [[ `docker inspect dit4c_{couchdb,etcd}; echo $?` ]]
do
    sleep 1
done

# Create highcommand and hipache servers
docker start dit4c_highcommand || docker run -d --name dit4c_highcommand \
    -v /var/log/dit4c_highcommand:/var/log \
    -v $CONFIG_DIR/dit4c-highcommand.conf:/etc/dit4c-highcommand.conf \
    --link dit4c_etcd:etcd \
    --link dit4c_couchdb:couchdb \
    dit4c/dit4c-platform-highcommand
docker start dit4c_hipache || docker run -d --name dit4c_hipache \
    --link dit4c_etcd:etcd \
    -v /var/log/dit4c_hipache:/var/log \
    --restart=always \
    dit4c/dit4c-platform-hipache

# Create SSL termination frontend
docker start dit4c_ssl || docker run -d --name dit4c_ssl \
    -p 80:80 -p 443:443 \
    -e DIT4C_DOMAIN=$DIT4C_DOMAIN \
    --volumes-from dit4c_ssl_keys:ro \
    --link dit4c_highcommand:dit4c-highcommand \
    --link dit4c_hipache:hipache \
    -v /var/log/dit4c_ssl:/var/log \
    dit4c/dit4c-platform-ssl

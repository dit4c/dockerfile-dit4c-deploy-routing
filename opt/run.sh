#!/bin/bash

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

# Establish if we need a local etcd, or we can reuse the host etcd
HOST_IP=$(/sbin/ip route|awk '/default/ { print $3 }')
curl -XHEAD -H "Connection: close" -v "http://$HOST_IP:2379/v2/stats/self"
if [[ $? == 0 ]]
then
  echo "Using host etcd"
  docker start dit4c_etcd || docker run -d --name dit4c_etcd \
    --restart=always \
    --expose 2379 -e ETCD_PORT_2379_TCP="tcp://$HOST_IP:2379" \
    svendowideit/ambassador
else
  echo "Using standalone etcd"
  docker start dit4c_etcd || docker run -d --name dit4c_etcd \
    -e ETCD_DATA_DIR=/var/lib/etcd \
    -e ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379,http://0.0.0.0:4001" \
    -v /var/lib/etcd \
    --restart=always \
    quay.io/coreos/etcd:v2.0.0_rc.1
fi

# Wait a little to ensure dit4c_etcd exist
until [[ `docker inspect dit4c_etcd; echo $?` ]]
do
    sleep 1
done

# Create hipache server
docker start dit4c_hipache || docker run -d --name dit4c_hipache \
    --link dit4c_etcd:etcd \
    --restart=always \
    dit4c/dit4c-platform-hipache

# Create SSL termination frontend
docker start dit4c_ssl || docker run -d --name dit4c_ssl \
    -p 80:80 -p 443:443 \
    -e DIT4C_DOMAIN=$DIT4C_DOMAIN \
    --volumes-from dit4c_ssl_keys:ro \
    --link dit4c_hipache:hipache \
    -v /var/log/dit4c_ssl:/var/log \
    dit4c/dit4c-platform-ssl

echo "Done configuring routing."
echo "Ensure you have a Hipache config for your portal."

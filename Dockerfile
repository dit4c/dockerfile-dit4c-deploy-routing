# DOCKER-VERSION 1.1.0
FROM centos:centos7
MAINTAINER t.dettrick@uq.edu.au

# Set defaults which should be overridden on run
ENV CONFIG_DIR "/opt/config"
ENV SSL_DIR "/opt/ssl"
ENV DIT4C_DOMAIN "dit4c.metadata.net"

RUN yum install -y docker

ADD /opt /opt

CMD ["bash", "/opt/run.sh"]
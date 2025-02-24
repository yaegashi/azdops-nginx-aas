FROM nginx:latest
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-server && \
    echo "root:Docker!" | chpasswd && \
    mkdir -p /run/sshd
COPY sshd_config /etc/ssh
COPY watch-nginx-config.sh /usr/local/bin
COPY 00-azdops-nginx-aas-setup.sh /docker-entrypoint.d
EXPOSE 2222

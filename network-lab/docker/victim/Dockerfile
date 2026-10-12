FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server nginx tcpdump curl iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /captures /srv/intranet
# The weak account the attacker will guess.
RUN useradd -m -s /bin/bash dev && echo 'dev:dev123' | chpasswd \
    && passwd -l root
# Password auth on + verbose logging (fingerprints appear in auth.log — good teaching).
RUN sed -i 's/#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo 'LogLevel VERBOSE' >> /etc/ssh/sshd_config
COPY intranet/ /srv/intranet/
COPY nginx.conf /etc/nginx/sites-enabled/default
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && rm -f /etc/nginx/sites-enabled/default.dpkg-dist
EXPOSE 22 80
ENTRYPOINT ["/entrypoint.sh"]

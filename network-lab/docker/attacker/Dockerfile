FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      nmap openssh-client sshpass curl python3 iproute2 \
    && rm -rf /var/lib/apt/lists/*
COPY attack.sh receiver.py /opt/
RUN chmod +x /opt/attack.sh
CMD ["sleep", "infinity"]

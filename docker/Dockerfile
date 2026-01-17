###############################################################
#              SCP:SL Server Docker Container                 #
#     Minimal Pterodactyl egg for SCP Secret Laboratory       #
###############################################################

FROM ubuntu:24.04

LABEL maintainer="MangoTeam"
LABEL description="SCP:Secret Laboratory server container"

# Install dependencies in a single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    lib32gcc-s1 \
    libicu-dev \
    unzip \
    && rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    update-ca-certificates && \
    useradd -m -d /home/container -s /bin/bash container

USER container
ENV USER=container \
    HOME=/home/container

WORKDIR /home/container

COPY --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/bin/bash", "/entrypoint.sh"]
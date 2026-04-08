###############################################################
#              SCP:SL Server Docker Container                 #
#     Pterodactyl egg — github.com/Ducstii/SCPSL-Egg         #
#     Author: ducstii                                         #
###############################################################

FROM ubuntu:24.04

LABEL maintainer="ducstii"
LABEL description="SCP: Secret Laboratory server container (ducstii / SCPSL-Egg)"
LABEL org.opencontainers.image.source="https://github.com/Ducstii/SCPSL-Egg"
LABEL org.opencontainers.image.authors="ducstii"
LABEL org.opencontainers.image.title="scpsl-egg"
LABEL org.opencontainers.image.description="Runtime image for the ducstii SCPSL-Egg (Pterodactyl)."

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

COPY --chown=container:container ./paths.inc.sh /paths.inc.sh
COPY --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/bin/bash", "/entrypoint.sh"]
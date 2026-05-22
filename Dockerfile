FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# Enable 32-bit architecture (required by SteamCMD and Wine)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg2 \
        software-properties-common \
        wget \
        xvfb \
        winbind \
        cabextract \
        lib32gcc-s1 \
    && rm -rf /var/lib/apt/lists/*

# Install Wine from WineHQ
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    rm -rf /var/lib/apt/lists/*

# Install winetricks
RUN wget -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /usr/local/bin/winetricks

# Create non-root steam user
RUN useradd -m -s /bin/bash steam && \
    mkdir -p /server/install /server/world /server/config /server/backups /server/mods /server/steamcmd && \
    chown -R steam:steam /server

# Copy scripts
COPY --chown=steam:steam scripts/ /server/scripts/
COPY --chown=steam:steam entrypoint.sh /server/entrypoint.sh
COPY --chown=steam:steam config/ /server/config-templates/
RUN chmod +x /server/entrypoint.sh /server/scripts/*.sh

USER steam
WORKDIR /server

# Install SteamCMD
RUN /server/scripts/install-steamcmd.sh

# Initialize Wine prefix (avoids first-run delays)
ENV WINEPREFIX=/home/steam/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all
RUN xvfb-run wine wineboot --init && \
    wineserver --wait

# Install .NET Framework 4.8 via winetricks (required by SE server)
RUN xvfb-run winetricks -q dotnet48 && \
    wineserver --wait

# Install vcrun2019 (commonly needed by SE)
RUN xvfb-run winetricks -q vcrun2019 && \
    wineserver --wait

EXPOSE 27016/udp

ENTRYPOINT ["/server/entrypoint.sh"]

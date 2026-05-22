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
        xauth \
        winbind \
        cabextract \
        lib32gcc-s1 \
        gettext-base \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Install Wine 8 (stable) from Debian repos instead of WineHQ
# Wine 8 has proven compatibility with SE dedicated server
RUN apt-get update && \
    apt-get install -y --install-recommends \
        wine \
        wine64 \
        wine32 \
    && rm -rf /var/lib/apt/lists/*

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
RUN xvfb-run wineboot --init && \
    wineserver --wait

# Install .NET Framework 4.8 via winetricks (required by SE server)
RUN xvfb-run winetricks -q dotnet48 && \
    wineserver --wait

# Install vcrun2019 (commonly needed by SE)
RUN xvfb-run winetricks -q vcrun2019 && \
    wineserver --wait

EXPOSE 27016/udp

HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD pgrep -f SpaceEngineersDedicated.exe || exit 1

ENTRYPOINT ["/server/entrypoint.sh"]

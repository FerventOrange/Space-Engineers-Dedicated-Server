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
        gosu \
    && rm -rf /var/lib/apt/lists/*

# Install Wine 8 (stable) from Debian repos instead of WineHQ
# Wine 8 has proven compatibility with SE dedicated server
RUN apt-get update && \
    apt-get install -y --install-recommends \
        wine \
        wine64 \
        wine32 \
    && rm -rf /var/lib/apt/lists/*

# Install winetricks (pinned to release tag for reproducible builds)
ARG WINETRICKS_TAG=20240105
RUN wget -O /usr/local/bin/winetricks \
      "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_TAG}/src/winetricks" && \
    chmod +x /usr/local/bin/winetricks

# Create non-root steam user
RUN useradd -m -s /bin/bash steam && \
    mkdir -p /server/install /server/world /server/config /server/backups /server/mods /server/steamcmd && \
    chown -R steam:steam /server

# Copy only the install script needed for build-time SteamCMD setup
COPY --chown=steam:steam scripts/install-steamcmd.sh /server/scripts/install-steamcmd.sh
RUN chmod +x /server/scripts/install-steamcmd.sh

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

# Switch to root for init wrapper setup
USER root

# Copy runtime scripts, entrypoint, and config templates (after expensive layers)
COPY --chown=steam:steam scripts/ /server/scripts/
COPY --chown=steam:steam entrypoint.sh /server/entrypoint.sh
COPY --chown=steam:steam config/ /server/config-templates/
COPY init.sh /server/init.sh
RUN chmod +x /server/entrypoint.sh /server/scripts/*.sh /server/init.sh

EXPOSE 27016/udp

HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD pgrep -f SpaceEngineersDedicated.exe || exit 1

ENTRYPOINT ["/server/init.sh"]

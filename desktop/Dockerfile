# Headless desktop for GUI apps from the OpenCode container
# Xvfb (:1) + Openbox + PulseAudio + RustDesk, bound to the self-hosted RustDesk server
FROM debian:bookworm-slim

# "latest" = newest release on every build; pin for reproducibility (e.g. 1.4.9)
ARG RUSTDESK_VERSION=latest
ARG PUID=1000
ARG PGID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    XDG_SESSION_TYPE=x11 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    NO_AT_BRIDGE=1

# --- Desktop base ---------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl jq \
      xvfb x11-xserver-utils x11-utils xauth dbus-x11 \
      openbox xterm menu \
      # Software OpenGL/EGL (Mesa llvmpipe) – RustDesk loads libEGL even without a GPU
      libegl1 libgles2 libgl1-mesa-dri libgbm1 \
      fonts-dejavu-core fonts-liberation \
      # Audio: PulseAudio with a virtual speaker
      pulseaudio pulseaudio-utils \
      tini procps \
 && rm -rf /var/lib/apt/lists/*

# --- RustDesk -------------------------------------------------------------------
# The .deb postinst wants to set up a systemd service; there is no systemd in the
# container -> temporarily replace systemctl with a no-op during installation.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64) rarch=x86_64 ;; arm64) rarch=aarch64 ;; *) echo "arch $arch not supported"; exit 1 ;; esac; \
    ver="$RUSTDESK_VERSION"; \
    if [ "$ver" = "latest" ]; then \
      ver="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | jq -r .tag_name)"; \
    fi; \
    echo "RustDesk $ver ($rarch)"; \
    curl -fsSL -o /tmp/rustdesk.deb \
      "https://github.com/rustdesk/rustdesk/releases/download/${ver}/rustdesk-${ver}-${rarch}.deb"; \
    printf '#!/bin/sh\nexit 0\n' > /usr/local/sbin/systemctl; chmod +x /usr/local/sbin/systemctl; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/rustdesk.deb libayatana-appindicator3-1; \
    rm -f /usr/local/sbin/systemctl /tmp/rustdesk.deb; \
    rm -rf /var/lib/apt/lists/*; \
    command -v rustdesk

# --- User matching the OpenCode container (same UID -> no permission issues on the X11 socket)
RUN groupadd -g "${PGID}" desktop \
 && useradd -m -u "${PUID}" -g "${PGID}" -s /bin/bash desktop \
 # Create ~/.config up front: otherwise Docker creates it as root when mounting .config/rustdesk
 && mkdir -p /home/desktop/.config && chown -R desktop:desktop /home/desktop \
 && mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix \
 # Stable machine ID: lives in the persistent config folder (start.sh creates it once).
 # Without this, every image build rolls a new one -> RustDesk assigns a new ID.
 && rm -f /etc/machine-id /var/lib/dbus/machine-id \
 && mkdir -p /var/lib/dbus \
 && ln -s /home/desktop/.config/rustdesk/machine-id /etc/machine-id \
 && ln -s /etc/machine-id /var/lib/dbus/machine-id

COPY start.sh /usr/local/bin/start-desktop
RUN chmod 0755 /usr/local/bin/start-desktop

USER desktop
WORKDIR /home/desktop

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/start-desktop"]

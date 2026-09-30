# OpenCode IDE image: upstream + runtime libraries for Qt5/PyQt5 GUIs and audio
ARG BASE_TAG=latest
FROM ghcr.io/joostme/opencode-docker:${BASE_TAG}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      # Qt5 runtime (PyQt5 wheels ship Qt itself but need these system libs)
      libgl1 libegl1 libglib2.0-0 libfontconfig1 libdbus-1-3 \
      libxkbcommon0 libxkbcommon-x11-0 libxrender1 libxi6 \
      libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
      libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 libxcb-xfixes0 libxcb-cursor0 \
      fonts-dejavu-core \
      # Testing helpers: xdpyinfo / xeyes
      x11-utils x11-apps \
      # Audio client: sound goes to the desktop container via PULSE_SERVER
      libpulse0 pulseaudio-utils libasound2-plugins alsa-utils sound-theme-freedesktop \
 && rm -rf /var/lib/apt/lists/* \
 # Redirect ALSA programs (aplay, speaker-test, ...) to PulseAudio as well
 && printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf
# No USER switch: the upstream entrypoint starts as root and drops privileges itself via gosu.

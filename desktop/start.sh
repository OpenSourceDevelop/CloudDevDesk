#!/usr/bin/env bash
# Starts Xvfb + Openbox + PulseAudio + RustDesk and binds RustDesk to the self-hosted server.
set -euo pipefail

: "${DISPLAY:=:1}"
: "${RESOLUTION:=1920x1080x24}"
: "${RUSTDESK_KEY:?RUSTDESK_KEY missing (contents of the hbbs id_ed25519.pub)}"
: "${RUSTDESK_PASSWORD:?RUSTDESK_PASSWORD missing (permanent access password)}"
# ID/relay server (set via compose; defaults for a shared Docker network)
: "${RUSTDESK_HBBS_HOST:=hbbs}"
: "${RUSTDESK_HBBR_HOST:=hbbr}"
: "${PULSE_DIR:=/tmp/pulse}"

log() { printf '[desktop] %s\n' "$*"; }
DISP_NUM="${DISPLAY#:}"
SOCK="/tmp/.X11-unix/X${DISP_NUM}"
PIDS=()

# --- 0. Stable machine ID (basis of the RustDesk ID) -----------------------------
mkdir -p "$HOME/.config/rustdesk"
MID="$HOME/.config/rustdesk/machine-id"
if [[ ! -s "$MID" ]]; then
  tr -d '-' < /proc/sys/kernel/random/uuid > "$MID"
  log "New machine ID created (stays fixed from now on)"
fi

# --- 1. X server ----------------------------------------------------------------
if [[ ! -w /tmp/.X11-unix ]]; then
  log "ERROR: /tmp/.X11-unix is not writable (host folder x11: chmod 1777)"; exit 1
fi
rm -f "$SOCK" "/tmp/.X${DISP_NUM}-lock"

log "Starting Xvfb ${DISPLAY} (${RESOLUTION})"
Xvfb "$DISPLAY" -screen 0 "$RESOLUTION" -nolisten tcp -ac +extension RANDR +extension GLX &
XVFB_PID=$!; PIDS+=("$XVFB_PID")

for _ in $(seq 1 30); do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  sleep 0.5
done
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || { log "Xvfb failed to start"; exit 1; }
log "X display ready (socket: $SOCK)"

# --- 2. Session bus + window manager ----------------------------------------------
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS

openbox --sm-disable &
xsetroot -solid '#2b2b2b' || true

# --- 3. Audio: PulseAudio with a virtual speaker -----------------------------------
# The socket lives in the shared folder -> the OpenCode container plays sound through it,
# RustDesk captures it from the monitor of the virtual speaker.
if [[ -w "$PULSE_DIR" ]]; then
  rm -f "$PULSE_DIR/native" "$PULSE_DIR/pid"
  export PULSE_RUNTIME_PATH="$PULSE_DIR"
  # --realtime/--high-priority=no: don't try to get priority via the system D-Bus (rtkit)
  pulseaudio -n --daemonize=no --exit-idle-time=-1 --disallow-exit \
    --realtime=no --high-priority=no --use-pid-file=no \
    --log-target=stderr --log-level=error \
    --load="module-native-protocol-unix socket=${PULSE_DIR}/native auth-anonymous=1" \
    --load="module-null-sink sink_name=virtual sink_properties=device.description=Virtual_Speaker" \
    --load="module-always-sink" &
  PIDS+=("$!")
  export PULSE_SERVER="unix:${PULSE_DIR}/native"
  for _ in $(seq 1 20); do pactl info >/dev/null 2>&1 && break; sleep 0.5; done
  if pactl info >/dev/null 2>&1; then
    pactl set-default-sink virtual || true
    pactl set-default-source virtual.monitor || true
    log "PulseAudio ready (socket: ${PULSE_DIR}/native)"
    AUDIO=Y
  else
    log "WARNING: PulseAudio failed to start – audio disabled"; AUDIO=N
  fi
else
  log "No writable ${PULSE_DIR} – audio disabled"; AUDIO=N
fi

# --- 4. Bind RustDesk to the self-hosted server -------------------------------------
# RustDesk2.toml only holds server/options and is rewritten on every start.
CFG="$HOME/.config/rustdesk"
mkdir -p "$CFG"
cat > "$CFG/RustDesk2.toml" <<EOF
rendezvous_server = '${RUSTDESK_HBBS_HOST}:21116'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '${RUSTDESK_HBBS_HOST}'
relay-server = '${RUSTDESK_HBBR_HOST}'
key = '${RUSTDESK_KEY}'
api-server = ''
verification-method = 'use-permanent-password'
approve-mode = 'password'
enable-audio = '${AUDIO}'
EOF

# Permanent password written directly into RustDesk.toml (the ID persists via the volume).
# RustDesk reads the plain-text value and encrypts it itself on the next save.
# "rustdesk --password" does not work without the root service, hence this approach.
# Note: the password must not contain a single quote (').
RDT="$CFG/RustDesk.toml"
touch "$RDT"
sed -i '/^password = /d' "$RDT"
if [[ -s "$RDT" ]]; then
  sed -i "1i password = '${RUSTDESK_PASSWORD}'" "$RDT"
else
  printf "password = '%s'\n" "$RUSTDESK_PASSWORD" > "$RDT"
fi

# Check that the ID server resolves (info only)
if getent hosts "$RUSTDESK_HBBS_HOST" >/dev/null; then
  log "ID server ${RUSTDESK_HBBS_HOST} -> $(getent hosts "$RUSTDESK_HBBS_HOST" | awk '{print $1}')"
else
  log "WARNING: ${RUSTDESK_HBBS_HOST} cannot be resolved – check RUSTDESK_SERVER / extra_hosts"
fi

# Server part of RustDesk only (no Flutter UI)
log "Starting RustDesk server"
rustdesk --server &
RD_PID=$!; PIDS+=("$RD_PID")

sleep 5
RID="$(rustdesk --get-id 2>/dev/null || true)"
log "========================================"
log " RustDesk ID: ${RID:-<not assigned yet – check the log>}"
log " Display:     ${DISPLAY} (${RESOLUTION})"
log " Audio:       ${AUDIO}"
log "========================================"

# --- 5. Supervise ----------------------------------------------------------------
shutdown() {
  log "Stopping ..."
  kill -TERM "${PIDS[@]}" 2>/dev/null || true
  wait || true
  exit 0
}
trap shutdown SIGTERM SIGINT

while kill -0 "$XVFB_PID" 2>/dev/null && kill -0 "$RD_PID" 2>/dev/null; do
  sleep 5 & wait $! || true
done
kill -0 "$XVFB_PID" 2>/dev/null || log "Xvfb exited – container will restart."
kill -0 "$RD_PID"   2>/dev/null || log "RustDesk exited – container will restart."
kill -TERM "${PIDS[@]}" 2>/dev/null || true
exit 1

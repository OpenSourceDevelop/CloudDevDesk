# OpenCode Stack

Browser-based development environment on the CloudLab server:
**OpenCode** (AI coding agent) and **code-server** (VS Code in the browser) work on the same code.
A **desktop sidecar** displays GUI apps such as PyQt5 via the self-hosted **RustDesk** server,
including mouse, keyboard and sound.

```
 Laptop / on the road
 ├─ Browser ── HTTPS ──▶ NPM ──▶ OpenCode Web ─┐
 ├─ Browser ── HTTPS ──▶ NPM ──▶ code-server  ─┤  Container "opencode"
 └─ RustDesk client ──▶ hbbs/hbbr (host) ◀── RustDesk ──┐   (/repos, .venv, mise)
                                                         │        │  DISPLAY=:1
                               Container "opencode-desktop"        │  PULSE_SERVER
                               Xvfb :1 · Openbox · PulseAudio ◀────┘  (shared sockets)

 Container "playwright-mcp"  ◀── MCP (http://playwright-mcp:8931/mcp) ── OpenCode
 Context7 (remote MCP)       ◀── MCP ── OpenCode
```

## Components

| Service | Image | Purpose |
|---|---|---|
| `opencode` | `cloudlab/opencode-ide:local` (based on `ghcr.io/joostme/opencode-docker`) | OpenCode Web (4096), code-server (8080), mise toolchains, Qt5 and audio client libraries |
| `opencode-desktop` | `cloudlab/opencode-desktop:local` (Debian bookworm) | Xvfb, Openbox, PulseAudio (virtual speaker), RustDesk in server mode |
| `playwright-mcp` | `mcr.microsoft.com/playwright/mcp` | Headless Chromium as an MCP tool for the agent |

## Directory layout (host)

```
/opt/cloudlab/stacks/opencode/
├── build/Dockerfile          # OpenCode image + Qt/audio libs
├── desktop/Dockerfile        # Desktop image
├── desktop/start.sh          # Starts Xvfb, PulseAudio and RustDesk
├── repos/                    # -> /repos           Code (agent + editor)
├── share/                    # -> ~/.local/share   OpenCode auth/sessions, code-server, mise
├── state/                    # -> ~/.local/state   OpenCode/mise state
├── config/                   # -> ~/.config        opencode.json, mise, zsh
│   ├── opencode/opencode.json
│   └── mise/config.toml
├── agents/                   # -> ~/.agents        Skills
├── ssh/                      # Deploy keys (read-only)
├── desktop-config/           # RustDesk ID, password, machine ID
├── x11/                      # Shared X11 socket   (chmod 1777)
└── pulse/                    # Shared audio socket
```

`compose.yaml` and `.env` are managed by **Arcane**. Arcane stores them internally under
`/app/data/projects/opencode/`. The corresponding host path is shown by the Arcane container's volume mapping.
Because Compose runs from inside Arcane, **all bind mounts use absolute paths**.

## Prerequisites

- Docker and Arcane on CloudLab, plus the external network `proxy-net` (Nginx Proxy Manager)
- Self-hosted RustDesk server (`rustdesk-hbbs` / `rustdesk-hbbr`, `network_mode: host`)
- **MSS clamping** to work around the bwCloud MTU issue (host MTU 1442, Docker 1500). Without this rule,
  TLS downloads hang in every container:
  ```bash
  sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  sudo apt install iptables-persistent        # persist the rule
  ```
- In the bwCloud security group: only TCP 80 and 443 (NPM / Let's Encrypt) are needed; 4096 and 8443 stay closed

## Installation

```bash
cd /opt/cloudlab/stacks/opencode
mkdir -p repos share state agents ssh config/opencode config/mise \
         build desktop desktop-config x11 pulse
chmod 1777 x11
chmod 700 share ssh

# OpenCode configuration (MCPs + agent permissions)
curl -fsSL https://raw.githubusercontent.com/joostme/opencode-docker/main/config/opencode/opencode.json \
  -o config/opencode/opencode.json

# Toolchains
cat > config/mise/config.toml <<'EOF'
[tools]
node = "22"
python = "3.13"
uv = "latest"
EOF

# copy build/Dockerfile, desktop/Dockerfile, desktop/start.sh here
chmod +x desktop/start.sh
sudo chown -R 1000:1000 .
```

Then create a project `opencode` in **Arcane**, paste `compose.yaml`, fill in the `.env` based on
`.env.example` and deploy. The first start takes a few minutes because both images are built
and the mise toolchains are installed.

### Nginx Proxy Manager (HTTPS)

The `opencode` container publishes no ports; it is only reachable through NPM on `proxy-net`.
Create two proxy hosts:

| | OpenCode | code-server |
|---|---|---|
| Domain | `opencode.<domain>` | `code.<domain>` |
| Forward | `http://opencode:4096` | `http://opencode:8080` |
| Options | Websockets ✔, Block Common Exploits ✔ | Websockets ✔, Block Common Exploits ✔ |
| SSL | Let's Encrypt, Force SSL, HTTP/2 | Let's Encrypt, Force SSL, HTTP/2 |

Add this to the **Advanced** tab of both hosts – OpenCode streams responses, and the default
buffering/60 s timeouts would cut off or delay long agent runs:

```nginx
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
proxy_buffering off;
client_max_body_size 100m;
```

To find the RustDesk key:
```bash
sudo docker exec rustdesk-hbbs cat /root/id_ed25519.pub    # or: sudo find / -name id_ed25519.pub -path '*rust*'
```

## Configuration (.env)

| Variable | Required | Meaning |
|---|---|---|
| `OPENCODE_SERVER_PASSWORD` | ✔ | Basic auth for the OpenCode web UI |
| `CODE_SERVER_PASSWORD` | ✔ | Password for code-server |
| `PUID` / `PGID` | | UID/GID of the host user (default 1000 = `debian`) |
| `OPENCODE_IMAGE_TAG` | | Version of the base image |
| `ANTHROPIC_API_KEY` etc. | | Provider keys, alternatively `/connect` in the UI |
| `CONTEXT7_API_KEY` | | Context7 MCP with a higher rate limit |
| `GH_TOKEN` | | GitHub CLI inside the container |
| `RUSTDESK_SERVER` | ✔ | Public name of the self-hosted RustDesk server |
| `RUSTDESK_KEY` | ✔ | Public key of hbbs |
| `RUSTDESK_PASSWORD` | ✔ | Permanent desktop password (no `'`) |
| `RUSTDESK_VERSION` | | RustDesk version in the desktop image (e.g. `1.4.9`) |
| `DESKTOP_RESOLUTION` | | Resolution of the virtual screen |

## Usage

| What | How |
|---|---|
| OpenCode Web | `https://opencode.<domain>`, user and password from `.env` |
| VS Code | `https://code.<domain>`, open the project folder **`/repos/<project>`**, not the host path |
| TUI on the same session | in the code-server terminal: `opencode attach http://127.0.0.1:4096` |
| GUI desktop | RustDesk client, ID from the `opencode-desktop` log, permanent password. Turn off **view-only mode** in the client. |
| Python project | `cd /repos/<project> && uv init && uv add PyQt5 && uv run python main.py` |
| Test sound | `paplay /usr/share/sounds/freedesktop/stereo/complete.oga` |
| More tools | add them to `config/mise/config.toml` and restart the container. **Do not** use `curl \| sh`, `pip --user` or `npm -g` — those install outside the volumes and are gone after a restart. |
| System libraries | add them to `build/Dockerfile` and redeploy |

GUI apps draw on the desktop automatically (`DISPLAY=:1`). `PULSE_SERVER` routes sound to the
desktop. `aplay` and other ALSA programs are routed there too via `/etc/asound.conf`.

## Maintenance

- **Updates:** bump the versions in `.env` and redeploy in Arcane. The images are rebuilt in the process.
- **Backup:** `repos/`, `share/` (contains `auth.json` with tokens), `config/`, `desktop-config/` and the `.env` from Arcane.
- **RustDesk ID:** the ID is tied to `desktop-config/machine-id`. Take this file along when migrating, otherwise RustDesk assigns a new ID.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Downloads hang, `SSL connection timeout`, `ECONNRESET` | MTU issue, MSS clamping rule missing (see Prerequisites). Check: `sudo iptables -t mangle -S FORWARD \| grep TCPMSS` |
| `opencode` unhealthy, `EACCES … .local/state` | Folder `state/` missing or not owned by 1000:1000 |
| `Permission denied` for mise or `.zshrc` | `sudo chown -R 1000:1000 share state config` |
| Arcane: `pull_policy is set to never` | Set `pull_policy` on the service or pull the image beforehand with `docker pull` |
| Playwright: `too many arguments … cli.js` | Newer image: no longer pass `cli.js` in `command:` |
| code-server: "Please enter a path that exists" | Use the container path `/repos/…`, not `/opt/cloudlab/…` |
| RustDesk: wrong password | Set `RUSTDESK_PASSWORD` and redeploy. `rustdesk --password` doesn't work without root, so `start.sh` writes the password directly into `RustDesk.toml`. |
| RustDesk: view only, no input | Turn off view-only mode in the **client** |
| RustDesk ID changes | If `desktop-config/machine-id` is missing or not owned by 1000, `start.sh` starts with a new ID |
| `Audio: N` in the desktop log | `pulse/` missing or not writable, or `~/.config` owned by root (desktop image too old) |
| Agent responses stop after ~60 s or arrive in one chunk | NPM advanced config missing (`proxy_read_timeout`, `proxy_buffering off`) |
| code-server terminal/editor won't connect | Websockets Support not enabled on the NPM proxy host |
| Harmless log messages | `libcuda.so.1`, `vsda … not found`, `authorized_keys not found`, `:21114/api/heartbeat` (RustDesk Pro only), `Owner of /tmp/.X11-unix` |

## Security

- OpenCode and code-server provide shell access. Use long passwords. Access is **HTTPS-only via NPM**; no container ports are published.
- Desktop container runs without capabilities (`cap_drop: ALL`). OpenCode only has the capabilities its entrypoint needs.
- `opencode.json` prevents the agent from reading `.env`, keys and `auth.json`, and blocks `sudo` and `docker`.
- This is container isolation, not a VM. `/repos` should only contain code the agent is allowed to see.

## Roadmap

1. ✅ Stack on CloudLab with cloud providers, MCPs and GUI desktop including audio
2. ✅ HTTPS via NPM, open ports closed
3. ⏳ WireGuard tunnel to the homelab and network `llm-net`
4. ⏳ Ollama on HomePC (RTX 5080) as a local provider in `opencode.json`

Details in [SPECIFICATION.md](SPECIFICATION.md).

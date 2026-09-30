# Specification – OpenCode Stack "CloudLab Dev Environment"

| | |
|---|---|
| **Project** | Browser-based AI development environment on CloudLab |
| **Owner / operator** | OpenDev |
| **Target system** | CloudLab (bwCloud, OpenStack, flavor L: 16 vCPU, 16 GB RAM, 400 GB), Debian, Docker + Arcane |
| **Status** | 2026-09-30 – stage 1 implemented |

---

## 1. Objectives

### 1.1 Background
Development has so far taken place locally. On the road, e.g. on eduroam with many blocked ports, there is no
full-featured environment. CloudLab already runs Docker, Arcane, Nginx Proxy Manager and a self-hosted
RustDesk server. At home, Ollama runs on a workstation with an RTX 5080.

### 1.2 Goal
An environment hosted on CloudLab that can be used with nothing but a browser and a RustDesk client:
AI coding agent, VS Code and a desktop for GUI applications, all working on **one** shared code base.

### 1.3 Mandatory criteria
| ID | Criterion |
|---|---|
| M1 | The OpenCode web UI is reachable via browser and password-protected. |
| M2 | VS Code (code-server) is reachable via browser, has its **own** password and works on the same code as OpenCode. |
| M3 | Code, sessions, credentials, toolchains and configuration survive restarts and rebuilds. |
| M4 | The agent has access to MCP tools: browser automation (Playwright) and library docs (Context7). |
| M5 | Python projects can be run with their own per-project dependencies (uv/venv). |
| M6 | PyQt5 GUIs run in the container and are visible and usable via the **self-hosted** RustDesk server. |
| M7 | The RustDesk connection uses a fixed password, requires no manual approval and has a stable ID. |
| M8 | The stack is operated entirely through Arcane (Compose + `.env`). |
| M9 | The stack does not start without passwords set. |

### 1.4 Optional criteria
| ID | Criterion | Status |
|---|---|---|
| W1 | Sound from GUI apps is transmitted via RustDesk. | implemented |
| W2 | The terminal UI (TUI) can attach to the same session as the web UI. | prepared (`opencode attach`), untested |
| W3 | Access only via HTTPS (NPM), no open ports. | open (stage 2) |
| W4 | Local LLM (Ollama/HomePC) as a provider via a WireGuard tunnel. | open (stage 3/4) |
| W5 | Versions of all images are pinned and therefore reproducible. | partial (RustDesk) |

### 1.5 Out of scope
- No multi-user operation; the system is intended for a single user.
- No VM isolation. Container isolation with hardening applies.
- No GPU in the container. Graphics are rendered in software (Mesa llvmpipe).
- No Docker-in-Docker for the agent.

---

## 2. Usage context

| Aspect | Description |
|---|---|
| Field of application | Firmware tools, Python/PyQt5 desktop tools, web projects, infrastructure scripts |
| Target audience | One developer (the operator) |
| Operating conditions | 24/7 operation, access from any network (including eduroam) |

---

## 3. System architecture

```
CloudLab host (Debian, Docker, Arcane, iptables MSS clamping)
│
├─ rustdesk-hbbs / rustdesk-hbbr        (existing, network_mode: host)
├─ nginx-proxy-manager                  (existing, network proxy-net)
│
└─ Project "opencode" (Arcane)
   ├─ opencode            Networks: proxy-net, backend    Ports 4096, 8443→8080
   │    OpenCode serve, code-server, sshd (internal), mise
   │    DISPLAY=:1, PULSE_SERVER=unix:/tmp/pulse/native
   ├─ opencode-desktop    Network: backend                no ports
   │    Xvfb :1, Openbox, PulseAudio (null sink), rustdesk --server
   │    extra_hosts: <RUSTDESK_SERVER> → host-gateway
   └─ playwright-mcp      Network: backend                no ports
        Chromium headless, MCP on :8931

Shared host folders:  x11/ (X11 socket) · pulse/ (audio socket)
```

### 3.1 Design decisions
| Decision | Rationale |
|---|---|
| Base image `joostme/opencode-docker` instead of a custom build | OpenCode and code-server come bundled, versions are pinned and agent permissions are preconfigured. |
| Custom image layer (`build/`) | Qt5 and audio libraries are missing from the base image and cannot be installed via apt at runtime. |
| Desktop as a separate sidecar | The graphics and remote stack stay separate from the IDE container and can be restarted independently. The OpenCode container stays lean. |
| X11 and audio via shared sockets | Apps run in their real environment (code, venv) and are still displayed on the desktop. |
| RustDesk in `--server` mode | The Flutter UI requires OpenGL and crashed in the container. The server part is sufficient for incoming connections. |
| Password via `RustDesk.toml` | `rustdesk --password` requires the root service, which is not available in the container. |
| Persistent machine ID | RustDesk derives its ID from the machine ID. Without a fixed machine ID, every build would produce a new ID. |
| `extra_hosts` → `host-gateway` | hbbs runs in the host network. This avoids the VM connecting to its own floating IP (hairpin NAT). |
| Absolute bind mounts | Arcane runs Compose from inside its own container. Relative paths would be resolved incorrectly there. |
| MSS clamping instead of MTU adjustment | Works for all existing and future Docker networks without recreating them (host MTU 1442). |

---

## 4. Functional requirements

### 4.1 OpenCode
| ID | Requirement |
|---|---|
| F-OC-01 | The web UI listens on port 4096 and is protected by HTTP basic auth (`OPENCODE_SERVER_USERNAME` / `_PASSWORD`). |
| F-OC-02 | Provider keys are set via `.env` or `/connect`. Credentials are stored in `share/`. |
| F-OC-03 | The MCP servers `playwright` (`http://playwright-mcp:8931/mcp`) and `context7` (remote) are configured in `config/opencode/opencode.json`. |
| F-OC-04 | Agent permissions: the agent must not read `.env`, `*.pem`, `*.key`, SSH keys or `auth.json`. `sudo`, `su` and `docker` are forbidden. Other shell commands require confirmation. |
| F-OC-05 | The TUI can use the same session via `opencode attach http://127.0.0.1:4096`. |

### 4.2 code-server
| ID | Requirement |
|---|---|
| F-CS-01 | Container port 8080, published as 8443, with its own password (`CODE_SERVER_PASSWORD`, required). |
| F-CS-02 | Working directory `/repos`, identical to OpenCode's. |
| F-CS-03 | Extensions are installed from Open VSX and stored in `share/code-server`. |

### 4.3 Toolchains and projects
| ID | Requirement |
|---|---|
| F-TC-01 | Runtimes (Node 22, Python 3.13, uv) are managed by mise from `config/mise/config.toml` and stored persistently in `share/mise`. |
| F-TC-02 | Python dependencies live per project in `/repos/<project>/.venv` (uv). |
| F-TC-03 | System libraries are added exclusively via `build/Dockerfile`. |

### 4.4 Desktop / GUI
| ID | Requirement |
|---|---|
| F-DT-01 | Virtual screen Xvfb `:1`, configurable resolution (`DESKTOP_RESOLUTION`, default 1920×1080×24). |
| F-DT-02 | Openbox window manager plus a D-Bus session bus. |
| F-DT-03 | GUI apps from `opencode` draw via `DISPLAY=:1` and the shared socket `x11/`. |
| F-DT-04 | RustDesk registers with the self-hosted hbbs using `RUSTDESK_SERVER` and `RUSTDESK_KEY`. |
| F-DT-05 | Access only with the permanent password (`verification-method = use-permanent-password`, `approve-mode = password`). |
| F-DT-06 | The RustDesk ID stays the same across restarts and image builds (`desktop-config/machine-id`). |
| F-DT-07 | If Xvfb or RustDesk fails, the container exits and is restarted automatically. |

### 4.5 Audio
| ID | Requirement |
|---|---|
| F-AU-01 | PulseAudio with a virtual speaker `virtual` in the desktop container. The socket is located at `pulse/native`. |
| F-AU-02 | Apps in `opencode` output sound via `PULSE_SERVER`. ALSA programs are redirected via `/etc/asound.conf`. |
| F-AU-03 | RustDesk transmits the monitor of the virtual speaker (`enable-audio = Y`). |
| F-AU-04 | If PulseAudio fails to start, the desktop keeps running without audio (`Audio: N` in the log). |

### 4.6 Operations
| ID | Requirement |
|---|---|
| F-BT-01 | Deployment as an Arcane project; both custom images are built via `build:` with `pull_policy: build`. |
| F-BT-02 | Health checks: `opencode` checks code-server `/healthz` and port 4096, `desktop` checks `xdpyinfo :1`. |
| F-BT-03 | Log rotation for all containers: json-file, 10 MB × 3. |
| F-BT-04 | The start phase of `opencode` may take up to 600 s (toolchain installation). |

---

## 5. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NF-01 | Security | All web entry points are password-protected. Empty passwords prevent startup (`:?` in Compose). |
| NF-02 | Security | `no-new-privileges` for all containers. `desktop` and `playwright-mcp` run with `cap_drop: ALL`, `opencode` only with the required capabilities. |
| NF-03 | Security | Port 22 of the container is not published. Dedicated deploy keys are used, not the host's SSH keys. |
| NF-04 | Resources | Limits: opencode 8 GB / 8 CPU, desktop 2 GB / 2 CPU, playwright 2 GB / 2 CPU, plus PID limits. |
| NF-05 | Persistence | No user data is lost after `docker compose down/up` or an image rebuild. |
| NF-06 | Portability | The stack can be moved to another Docker host with an `.env` and the host folders. |
| NF-07 | Network | It works despite the bwCloud MTU of 1442 (MSS clamping on the host). |
| NF-08 | Maintainability | Versions are controlled via `.env`. The upstream images provide a changelog. |

---

## 6. Data and interfaces

### 6.1 Persistent data
| Host folder | Container path | Contents | Backup |
|---|---|---|---|
| `repos/` | `/repos` | Source code, `.venv` | ✔ |
| `share/` | `~/.local/share` | OpenCode auth/sessions, code-server, mise | ✔ (contains tokens) |
| `state/` | `~/.local/state` | OpenCode and mise state | – |
| `config/` | `~/.config` | `opencode.json`, mise, zsh, code-server | ✔ |
| `agents/` | `~/.agents` | Skills | ✔ |
| `ssh/` | `~/.ssh-keys` (ro) | Deploy keys | ✔ |
| `desktop-config/` | `~/.config/rustdesk` | RustDesk ID, configuration, machine ID | ✔ |
| `x11/`, `pulse/` | `/tmp/.X11-unix`, `/tmp/pulse` | Runtime sockets | – |

### 6.2 Network interfaces
| Interface | Direction | Port / protocol |
|---|---|---|
| OpenCode Web | external → opencode | TCP 4096 (HTTP) |
| code-server | external → opencode | TCP 8443 → 8080 (HTTP) |
| MCP Playwright | opencode → playwright-mcp | TCP 8931 (internal) |
| RustDesk registration | desktop → hbbs (host) | UDP/TCP 21116 |
| RustDesk relay | desktop → hbbr (host) | TCP 21117 |
| X11 / audio | opencode → desktop | Unix sockets (shared folders) |

---

## 7. Acceptance criteria

| No. | Test | Expected result | Status |
|---|---|---|---|
| A1 | Open `http://<server>:4096` | Login prompt, then the OpenCode UI | ✔ |
| A2 | Open `http://<server>:8443` | code-server login, then the `/repos` folder | ✔ |
| A3 | Agent: "Open example.com with Playwright" | Tool call `playwright_*`, page title is reported | open |
| A4 | `docker exec opencode curl https://open-vsx.org` | HTTP 200 in under 2 s | ✔ |
| A5 | `uv add PyQt5 && uv run python main.py` | Window appears on the RustDesk desktop | ✔ |
| A6 | Click and type in the window | Input is received | ✔ |
| A7 | Click the button in the test app | Click sound audible on the client | open |
| A8 | Redeploy the stack twice in a row | RustDesk ID unchanged, no "New machine ID created" message | open |
| A9 | Empty password in `.env` | Deploy aborts with an error message | ✔ |
| A10 | Recreate the containers | Sessions, extensions and venv are preserved | open |

---

## 8. Known limitations

- HTTP without TLS on 4096/8443 until stage 2 (NPM) is implemented.
- A RustDesk connection without a direct route goes through the relay. Latency depends on the connection.
- Software rendering: GUI performance is sufficient for tools and tests, not for 3D.
- The heartbeat to `:21114` (RustDesk Pro API) fails. This is expected with the OSS server and harmless.
- The upstream entrypoint's `mise self-update` runs as root. This is why `state/` must be created beforehand.
- Upstream images tagged `latest` may change their arguments (e.g. Playwright MCP). Pinning is recommended.

---

## 9. Roadmap

| Stage | Content | Status |
|---|---|---|
| 1 | Stack on CloudLab: OpenCode, code-server, MCPs, desktop with RustDesk, audio | ✔ |
| 2 | NPM proxy hosts with HTTPS for 4096/8080, remove `ports:`, close the security group | open |
| 3 | WireGuard: gateway LXC in the homelab connects outbound to CloudLab. Network `llm-net`, DNAT only to `HomePC:11434` | open |
| 4 | Ollama as an OpenAI-compatible provider in `opencode.json`, `OLLAMA_CONTEXT_LENGTH` ≥ 32768, Wake-on-LAN for HomePC, cloud provider as fallback | open |
| 5 | Version pinning of all images and backup automation | open |

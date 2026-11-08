# Recap Studio Server

[Recap Studio](https://github.com/iEatNoodlez/RecapStudio) as a server: the same app, on a Linux machine at home (a NAS, a mini PC, a spare computer), used from a browser on any of your devices. It's one file, an AppImage, that runs on any 64-bit Linux: it carries its own Python, its own C library and everything else, runs as a service, sits behind a login and updates itself. Or run it with Docker: the same server as an image. On a QNAP NAS, it's a package for App Center.

It's the app's own code, from its releases, built without the window. This repository holds what makes it a server you install: the install script, the Docker image, the build, and the server's releases.

## What it needs

- A 64-bit machine running any Linux, old or new: a PC (x86_64), or 64-bit ARM (aarch64: a Raspberry Pi 4 or 5 with the 64-bit Raspberry Pi OS, an ARM NAS, an ARM server). The AppImage brings its own C library (glibc 2.35), so it doesn't matter which the system has, or whether it has glibc at all (Alpine's musl). The x86_64 one was tried on Ubuntu 18.04, 20.04 and 24.04, Debian 10 and 11, CentOS 7 and Alpine 3.20; the ARM one is checked on GitHub's ARM machines (Alpine, CentOS 7, the Docker image) and hasn't been on a Pi yet. 32-bit ARM isn't possible: the libraries the app reads and voices with aren't made for it.
- The install script needs systemd (Ubuntu, Debian, Fedora and most others have it). Elsewhere (Alpine, a NAS), use [Docker](#with-docker), or start the AppImage from a service of your own. A QNAP NAS has a package of its own: [On a QNAP NAS](#on-a-qnap-nas).
- ffmpeg from your distribution is better than the AppImage's own copy, which can't use the graphics card: `sudo apt install ffmpeg` (Fedora: from RPM Fusion). With an NVIDIA card, the videos are then encoded on it.
- Space: a recap takes several GB.

## Installing

```bash
curl -fsSLO https://raw.githubusercontent.com/iEatNoodlez/RecapStudio-Cloud/main/install.sh
less install.sh
sudo bash install.sh
```

`install.sh` installs Full Suite (the app with [Recap Studio's plugins](https://github.com/iEatNoodlez/RecapStudio-Plugins#readme)) on port 8780. `sudo bash install.sh lite --port 9000` installs Lite on another port. It:
- makes a system user, `recap-studio`, that the server runs as;
- downloads the latest server AppImage from this repository's releases, checked against the SHA-256 GitHub lists for it, into `/opt/recap-studio`;
- writes and starts a systemd service, `recap-studio`, that starts at boot;
- prints the address to open and the setup code.

Settings, API keys and the voice model go in `/var/lib/recap-studio/recap-studio`. Projects go in `/var/lib/recap-studio/Recap Studio`; Settings → Projects folder moves them.

**Without the script:** download `Recap-Studio-Server-Full-<version>-x86_64.AppImage` (or Lite; `-aarch64` on ARM) from the [Releases](https://github.com/iEatNoodlez/RecapStudio-Cloud/releases), `chmod +x` it and start it. It runs as a server by itself, keeping its data in `~/.local/share/recap-studio`. Start it from a service of your own to keep it running. Without FUSE (Alpine, a container), add `--appimage-extract-and-run`: it unpacks itself each time it starts, or `--appimage-extract` once unpacks it into `squashfs-root/`, to start with `squashfs-root/AppRun --server`.

## With Docker

The image is the server AppImage, unpacked, on Debian 12 with Debian's ffmpeg (which can use an NVIDIA card). It runs anywhere Docker does: a NAS's container app (Synology's Container Manager, QNAP's Container Station, Unraid, TrueNAS), Portainer, or `docker compose` on any Linux.

- `ghcr.io/ieatnoodlez/recap-studio-server:latest`: Lite; `:latest-full`: Full Suite. Each release also has its own tags (`:0.4.1`, `:0.4.1-full`). Each tag holds the image for x86_64 and for 64-bit ARM: Docker pulls your machine's.
- With [`docker/docker-compose.yml`](docker/docker-compose.yml) in a folder of its own: `docker compose up -d`, then `docker logs recap-studio` for the setup code, and open `http://<the machine>:8780/`.
- **Its data** (settings, the login, the voice model, and the projects in `Recap Studio/`) is in `/data`: keep it on a volume. It runs as `PUID`:`PGID` (1000:1000 unless you set them; Unraid's are 99 and 100), and makes `/data` theirs on its first start.
- **A NAS share** goes in as a second volume (`/mnt/nas/recaps:/recaps`), then Settings → Projects folder, or a plugin's folder, can use `/recaps`.
- **`shm_size: 1gb`**, as in the example: the drawing processes share memory, and Docker's 64 MB is too small for 1080p.
- **Updates** come as a newer image: `docker compose pull`, then `docker compose up -d`. Settings → Updates still tells you when one is out. A restart from the app closes it, and the restart policy (`unless-stopped`) starts it again.
- **An NVIDIA card** for encoding needs NVIDIA's container toolkit on the machine, and the `deploy:` lines in the example.
- **Ollama** on the same machine is `http://host.docker.internal:11434` from inside the container (on Linux, add `extra_hosts: ["host.docker.internal:host-gateway"]`).
- **Claude Code** isn't in the image: use its MCP server from your own computer, below.

## On a QNAP NAS

A QNAP with QTS 5 or later (or QuTS hero 5 or later) takes the QNAP package, with nothing else installed: no Container Station, no other package. An Intel or AMD model takes the `-x86_64.qpkg`; a 64-bit ARM one (a TS-x33, say) the `-aarch64.qpkg`, which hasn't been tried on an ARM QNAP yet.

1. Download `Recap-Studio-Server-Full-<version>-x86_64.qpkg` (or Lite, or `-aarch64`) from the [Releases](https://github.com/iEatNoodlez/RecapStudio-Cloud/releases).
2. QNAP doesn't sign it, so let App Center take it: **App Center → Settings (the gear) → General → Allow installation of applications without a valid digital signature**.
3. **App Center → Install Manually** (the icon beside the gear), and choose the `.qpkg`.
4. Its first start unpacks the app into the package's folder (about 1 GB), which takes a minute or two. Then **Open** in App Center opens it (port 8780).

The first visit's **setup code** is in QTS's event log (**QuLog Center**, from "Recap Studio Server") and in `logs/recap-studio.log` in the package's folder. Over SSH, as admin, `/etc/init.d/RecapStudio.sh status` shows it as well.

**Why a package of its own:** QTS 5's C library (glibc 2.21, from 2015) is older than the app needs. The package holds the same server AppImage as the other Linux releases, which brings its own glibc, the way MyQNAP's Sonarr package does: the app's programs start through it, and QTS's own keep QTS's.

**Where its files go:** in the package's folder, on the volume you chose (`/share/CACHEDEV1_DATA/.qpkg/RecapStudio`, say): settings, the login and the voice model in `data/recap-studio`, projects in `Recap Studio`, the log in `logs`. To reach the projects over the network, move them to a shared folder with **Settings → Projects folder** (`/share/Multimedia/Recap Studio`, say). **Removing the package in App Center deletes its folder**, with the projects in it if they're still there.

**Updates:** **Settings → Updates → Install** updates the app inside the package, which starts it again. Installing a newer `.qpkg` over it replaces the app and keeps the rest of its folder: settings, the login, projects.

**Options** (`--allow-plugins`, `--port 9000`; see [The AppImage's options](#the-appimages-options)) go in a file named `options` in the package's folder, on one line. Then stop and start it in App Center.

**A forgotten password:** over SSH, as admin, `/etc/init.d/RecapStudio.sh reset-login`, then visit it again with the new setup code.

The package runs as QTS's admin, as App Center's packages do.

## The first visit

Open `http://<the server>:8780/`. The first visit asks for the **setup code** the server writes in its log, so nobody else on your network can set it up first:

```bash
journalctl -u recap-studio | grep "setup code"
```

With Docker: `docker logs recap-studio | grep "setup code"`, or your container app's log.

Then choose a username and password. Every visit after that signs in with them. A browser stays signed in for 30 days. After five wrong passwords, an address has to wait ten minutes.

**Settings → Server** changes the username and password (every browser is signed out), shows the API key, and sets the address and port it listens on from its next start. A port on its command line wins over it: `install.sh` names one (`--port`) in the service.

**Forgot the password?** Forget the login, then visit it again with the new setup code from the log:

```bash
sudo -u recap-studio env HOME=/var/lib/recap-studio XDG_DATA_HOME=/var/lib/recap-studio \
  /opt/recap-studio/recap-studio.AppImage --reset-login
```

## Reaching it

- **At home:** `http://<the server>:8780/` from any browser on your network. If a firewall runs on the server (`ufw`, `firewalld`), let that port through.
- **From anywhere else:** never forward the port to the internet. Use [Tailscale](https://tailscale.com) (the server's Tailscale address, encrypted, nothing to set up) or a reverse proxy with HTTPS on its own (sub)domain. With [Caddy](https://caddyserver.com), which gets the certificate itself:
  ```
  recap.example.com {
      reverse_proxy 127.0.0.1:8780
  }
  ```
  With nginx, pass the address the browser used and allow big uploads:
  ```
  location / {
      proxy_pass http://127.0.0.1:8780;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      client_max_body_size 0;
  }
  ```
  It needs its own (sub)domain: it can't run under a path (`example.com/recap`) yet.

Over plain HTTP, someone on the same network could read the sign-in cookie, as with any HTTP site. HTTPS (a reverse proxy, or Tailscale) keeps it private.

## Using it

It's the whole app, in the browser:
- **Chapters** come from your sources and sites, as in the app, or from the device you're on: drop images, .zip or .cbz files on the Chapters tab, or **browse**. **Import folder…** takes a folder on the server (your NAS's shares) by its path; the `recap-studio` user needs to be able to read it (for example, add it to the group that owns it).
- **Project files** (.recap) open from a path on the server, or sent from your device.
- **Videos** play in the Video tab, and download from there.
- **Claude Code** runs as the `recap-studio` user: install it for that user and sign in once, in a terminal on the server: `sudo -u recap-studio -H bash`, then Claude Code's installer and `claude auth login`.
- **Claude Code's MCP server** from your own computer, with the API key from Settings → Server:
  ```bash
  claude mcp add --transport http recap-studio http://<the server>:8780/mcp --header "X-Api-Key: <the key>"
  ```

What a server doesn't do:
- **Site check**, which needs the app's own window.
- **The phone page:** open the server's address in the phone's browser instead.
- **Show in folder.**

**Plugins:** Recap Studio's own plugins install from Settings → Plugins as usual. Source plugins and plugin lists run code on the server, so the browser can only add them when the server was started with `--allow-plugins`. Add it to the service's `ExecStart=` line in `/etc/systemd/system/recap-studio.service`, then run `sudo systemctl daemon-reload` and restart the service.

## Updates

Like the app: it checks this repository's releases when it starts, and **Settings → Updates → Install** downloads the new AppImage, checks its SHA-256 and puts it in place. The service then starts it again.

## The AppImage's options

| | |
|---|---|
| `--server` | Run as a server (the server AppImage does by itself) |
| `--host 0.0.0.0` | The address to listen on (0.0.0.0: every network the machine is on); wins over Settings → Server |
| `--port 8780` | The port; wins over Settings → Server |
| `--allow-plugins` | Let source plugins and plugin lists be added from the browser |
| `--reset-login` | Forget the login, then stop: the next visit sets it up again |

## Removing it

```bash
sudo bash install.sh --uninstall          # the service and the app; projects and settings stay
sudo bash install.sh --uninstall --purge  # those too, and the recap-studio user
```

## How it's built

Each release is built by GitHub Actions (`.github/workflows/build.yml`), for each architecture on a GitHub machine of that kind: Ubuntu 22.04, x86_64 and ARM. It builds from RecapStudio at the tag `app-version` names, with that repository's `packaging/linux/build.sh <version> <edition> --server`. That's the desktop AppImage's build without Qt's window, about half the size, plus its own C library: the build machine's glibc and the libraries the app needs from outside it, with each of its programs (Python, ffmpeg) started through that glibc's loader (`packaging/linux/own_glibc.sh`). Full Suite's plugins are the ones that app release pins. The workflow then starts each on Alpine and CentOS 7 to check they run, builds the Docker images from them (`docker/Dockerfile`), checks each answers, and pushes them to GitHub's container registry, one tag for both architectures.

The QNAP packages are made from those AppImages by `qnap/build-qpkg.sh`, with QNAP's [QDK](https://github.com/qnap-dev/QDK) (`qbuild`), and checked by their bytes (`qnap/check-qpkg.sh`). `qnap/shared/RecapStudio.sh` is the package's service script, which App Center runs: it unpacks the AppImage into the package's folder and keeps the app running.

## License

MIT.

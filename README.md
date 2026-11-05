# Recap Studio Server

[Recap Studio](https://github.com/iEatNoodlez/RecapStudio) as a server: the same app, on a Linux machine at home (a NAS, a mini PC, a spare computer), used from a browser on any of your devices. It's one file, an AppImage, with no Docker: it carries its own Python and everything else, runs as a service, sits behind a login and updates itself.

It's the app's own code, from its releases, built without the window. This repository holds what makes it a server you install: the install script, the build, and the server's releases.

## What it needs

- A 64-bit PC (x86-64) running Linux from 2022 or later: Ubuntu 22.04, Debian 12, Fedora 36, or newer (glibc 2.35 or later). The install script also needs systemd, which those all have.
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

**Without the script:** download `Recap-Studio-Server-Full-<version>-x86_64.AppImage` (or Lite) from the [Releases](https://github.com/iEatNoodlez/RecapStudio-Cloud/releases), `chmod +x` it and start it. It runs as a server by itself, keeping its data in `~/.local/share/recap-studio`. Start it from a service of your own to keep it running.

## The first visit

Open `http://<the server>:8780/`. The first visit asks for the **setup code** the server writes in its log, so nobody else on your network can set it up first:

```bash
journalctl -u recap-studio | grep "setup code"
```

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

Each release is built by GitHub Actions (`.github/workflows/build.yml`). It runs on Ubuntu 22.04, from RecapStudio at the tag `app-version` names, with that repository's `packaging/linux/build.sh <version> <edition> --server`. That's the desktop AppImage's build without Qt's window, about half the size. Full Suite's plugins are the ones that app release pins.

## License

MIT.

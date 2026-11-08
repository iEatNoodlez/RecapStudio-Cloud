Recap Studio {version} as a server, for a Linux machine you reach from a browser: the app from [RecapStudio {app}](https://github.com/iEatNoodlez/RecapStudio/releases/tag/{app}), with no window, behind a login.

- **Recap Studio Server Full Suite**: `Recap-Studio-Server-Full-{version}-x86_64.AppImage`, with [Recap Studio's plugins](https://github.com/iEatNoodlez/RecapStudio-Plugins#readme) built in.
- **Recap Studio Server Lite**: `Recap-Studio-Server-Lite-{version}-x86_64.AppImage`, the whole app with no plugins.
- **For 64-bit ARM** (a Raspberry Pi 4 or 5, an ARM NAS or server): the same two as `-aarch64.AppImage`.
- **For a QNAP NAS** (QTS 5 or later): `Recap-Studio-Server-Full-{version}-x86_64.qpkg` and `-Lite-` for an Intel or AMD model, `-aarch64.qpkg` for a 64-bit ARM one, installed with App Center's **Install Manually**. The x86_64 package runs on QTS 5.2; the ARM one hasn't been tried on an ARM QNAP yet.

Each runs on any 64-bit Linux of its kind, old or new, Alpine's included: it brings its own C library.

**With Docker:** `ghcr.io/ieatnoodlez/recap-studio-server:{version}` (Lite) and `:{version}-full` (Full Suite), also as `:latest` and `:latest-full`. Each tag holds both architectures: Docker pulls the one for your machine.

**Installing:** `sudo bash install.sh` from this repository sets it up as a service, or start an AppImage yourself. On a QNAP, install the `.qpkg`. Copies update themselves from these releases. See the [README](https://github.com/iEatNoodlez/RecapStudio-Cloud#readme).

Recap Studio {version} as a server, for a Linux machine you reach from a browser: the app from [RecapStudio {app}](https://github.com/iEatNoodlez/RecapStudio/releases/tag/{app}), with no window, behind a login.

- **Recap Studio Server Full Suite**: `Recap-Studio-Server-Full-{version}-x86_64.AppImage`, with [Recap Studio's plugins](https://github.com/iEatNoodlez/RecapStudio-Plugins#readme) built in.
- **Recap Studio Server Lite**: `Recap-Studio-Server-Lite-{version}-x86_64.AppImage`, the whole app with no plugins.

Each runs on any 64-bit Linux, old or new, Alpine's included: it brings its own C library.

**With Docker:** `ghcr.io/ieatnoodlez/recap-studio-server:{version}` (Lite) and `:{version}-full` (Full Suite), also as `:latest` and `:latest-full`.

**Installing:** `sudo bash install.sh` from this repository sets it up as a service, or start an AppImage yourself. Copies update themselves from these releases. See the [README](https://github.com/iEatNoodlez/RecapStudio-Cloud#readme).

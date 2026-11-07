# Recap Studio Server as a Docker image: the server AppImage (its own glibc inside), unpacked, on Debian 12 with
# Debian's ffmpeg, which can encode on an NVIDIA card through NVIDIA's container toolkit. The workflow builds it from
# the release's AppImage (.github/workflows/build.yml); by hand, with the AppImage beside this file:
#
#   docker build --build-arg APPIMAGE=Recap-Studio-Server-Lite-0.4.1-x86_64.AppImage -t recap-studio-server docker/
#
# Its data (settings, the login, projects) is in /data; it listens on 8780; it runs as PUID:PGID (1000:1000 unless
# they're set). Updates come as a newer image: the app's own updater says so (RECAP_CONTAINER). See
# docker-compose.yml and the README's "With Docker".

# the AppImage, unpacked: its static runtime needs no FUSE, and the file itself stays out of the image
FROM debian:12-slim AS unpack
ARG APPIMAGE=recap-studio.AppImage
COPY ${APPIMAGE} /tmp/recap-studio.AppImage
RUN cd /tmp && chmod 755 recap-studio.AppImage && ./recap-studio.AppImage --appimage-extract > /dev/null \
 && test -f squashfs-root/SERVER && test -d squashfs-root/glibc && chmod -R a+rX squashfs-root

FROM debian:12-slim
# ffmpeg (the app prefers the system's), fonts for the video's text (the app's fallbacks: DejaVu and Liberation),
# certificates, time zones (TZ), and tini to pass on signals and reap the drawing processes
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg fonts-dejavu-core fonts-liberation ca-certificates tzdata tini \
 && rm -rf /var/lib/apt/lists/*
COPY --from=unpack /tmp/squashfs-root /opt/recap-studio
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh && mkdir -p /data

# settings and the voice model in /data/recap-studio, projects in /data/Recap Studio (until Settings moves them)
ENV HOME=/data XDG_DATA_HOME=/data XDG_DOCUMENTS_DIR=/data LANG=C.UTF-8 \
    RECAP_CONTAINER=1 RECAP_SUPERVISED=1 \
    RECAP_CODE_PLACE="docker logs recap-studio (or your container app's log)" \
    NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
VOLUME /data
EXPOSE 8780
# (a restart or an update closes the app: the restart policy starts it again)
HEALTHCHECK --interval=1m --timeout=10s --start-period=2m \
  CMD ["/opt/recap-studio/python/bin/python3", "-I", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8780/api/auth', timeout=5)"]
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh", "/opt/recap-studio/AppRun", "--server", "--host", "0.0.0.0", "--port", "8780"]

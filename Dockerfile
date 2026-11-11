# Authoritative game server for Render: the Godot editor binary run headless, no export templates.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip nginx-light \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN curl -sSLo /tmp/godot.zip "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /app/godot \
 && chmod +x /app/godot \
 && rm /tmp/godot.zip

COPY . /app

# Imports the project once at build time so the server starts fast.
RUN ./godot --headless --path /app --import

# nginx listens on PORT (Render sets it) and sends WebSocket connections to the Godot server
# on 9090, and browsers to the game page.
CMD ["/app/deploy/start.sh"]

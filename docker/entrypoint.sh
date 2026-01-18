#!/bin/bash

echo "[ENTRYPOINT] Starting entrypoint script..."

# Set defaults for empty variables
export SCPSL_PORT=${SCPSL_PORT:-7777}
echo "[ENTRYPOINT] SCPSL_PORT set to: ${SCPSL_PORT}"

# The install script installs to /mnt/server/.bin/SCPSLDS
# In Pterodactyl, /mnt/server is typically the server data directory
# Find where the server files are and change to that directory

SERVER_DIR=".bin/SCPSLDS"
echo "[ENTRYPOINT] Looking for server files..."

if [ -d "/mnt/server/.bin/SCPSLDS" ]; then
    # Files installed in /mnt/server (where install.sh puts them)
    echo "[ENTRYPOINT] Found server files in /mnt/server/.bin/SCPSLDS"
    cd /mnt/server || exit 1
    echo "[ENTRYPOINT] Changed directory to: $(pwd)"
elif [ -d "/home/container/.bin/SCPSLDS" ]; then
    # Files in /home/container
    echo "[ENTRYPOINT] Found server files in /home/container/.bin/SCPSLDS"
    cd /home/container || exit 1
    echo "[ENTRYPOINT] Changed directory to: $(pwd)"
elif [ -d ".bin/SCPSLDS" ]; then
    # Already in the right directory
    echo "[ENTRYPOINT] Found server files in current directory: $(pwd)"
    : # no-op, stay where we are
else
    echo "[ERROR] Server directory .bin/SCPSLDS not found!"
    echo "[ERROR] Current directory: $(pwd)"
    echo "[ERROR] /mnt/server/.bin/SCPSLDS exists: $([ -d /mnt/server/.bin/SCPSLDS ] && echo 'YES' || echo 'NO')"
    echo "[ERROR] /home/container/.bin/SCPSLDS exists: $([ -d /home/container/.bin/SCPSLDS ] && echo 'YES' || echo 'NO')"
    exit 1
fi

# Verify LocalAdmin exists
echo "[ENTRYPOINT] Verifying LocalAdmin exists at: $SERVER_DIR/LocalAdmin"
if [ ! -f "$SERVER_DIR/LocalAdmin" ]; then
    echo "[ERROR] LocalAdmin executable not found in $SERVER_DIR"
    echo "[ERROR] Server installation may be incomplete."
    exit 1
fi
echo "[ENTRYPOINT] LocalAdmin found!"

# Make sure LocalAdmin is executable
chmod +x "$SERVER_DIR/LocalAdmin" 2>/dev/null || true
echo "[ENTRYPOINT] LocalAdmin permissions set"

# Display startup info
echo "=========================================="
echo "  SCP:SL Server Starting"
echo "=========================================="
echo "Port: ${SCPSL_PORT}"
echo "Server directory: $(pwd)/$SERVER_DIR"
echo "=========================================="

# Check if STARTUP variable is set
if [ -z "${STARTUP}" ]; then
    echo "[WARNING] STARTUP variable is not set, using default command"
    echo "[ENTRYPOINT] Executing: cd $SERVER_DIR && ./LocalAdmin ${SCPSL_PORT}"
    cd "$SERVER_DIR" || exit 1
    exec ./LocalAdmin "${SCPSL_PORT}"
else
    # Replace Startup Variables (Pterodactyl template variables)
    echo "[ENTRYPOINT] STARTUP variable: ${STARTUP}"
    MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
    echo "[ENTRYPOINT] Modified startup: ${MODIFIED_STARTUP}"
    echo "Executing: ${MODIFIED_STARTUP}"
    
    # Run the Server
    eval "${MODIFIED_STARTUP}"
fi
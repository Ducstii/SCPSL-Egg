#!/bin/bash

# Set defaults for empty variables
export SCPSL_PORT=${SCPSL_PORT:-7777}

# The install script installs to /mnt/server/.bin/SCPSLDS
# In Pterodactyl, /mnt/server is typically the server data directory
# Find where the server files are and change to that directory

SERVER_DIR=".bin/SCPSLDS"

if [ -d "/mnt/server/.bin/SCPSLDS" ]; then
    # Files installed in /mnt/server (where install.sh puts them)
    cd /mnt/server || exit 1
elif [ -d "/home/container/.bin/SCPSLDS" ]; then
    # Files in /home/container
    cd /home/container || exit 1
elif [ -d ".bin/SCPSLDS" ]; then
    # Already in the right directory
    : # no-op, stay where we are
else
    echo "[ERROR] Server directory .bin/SCPSLDS not found!"
    echo "[ERROR] Current directory: $(pwd)"
    echo "[ERROR] /mnt/server/.bin/SCPSLDS exists: $([ -d /mnt/server/.bin/SCPSLDS ] && echo 'YES' || echo 'NO')"
    echo "[ERROR] /home/container/.bin/SCPSLDS exists: $([ -d /home/container/.bin/SCPSLDS ] && echo 'YES' || echo 'NO')"
    exit 1
fi

# Verify LocalAdmin exists
if [ ! -f "$SERVER_DIR/LocalAdmin" ]; then
    echo "[ERROR] LocalAdmin executable not found in $SERVER_DIR"
    echo "[ERROR] Server installation may be incomplete."
    exit 1
fi

# Make sure LocalAdmin is executable
chmod +x "$SERVER_DIR/LocalAdmin" 2>/dev/null || true

# Display startup info
echo "=========================================="
echo "  SCP:SL Server Starting"
echo "=========================================="
echo "Port: ${SCPSL_PORT}"
echo "Server directory: $(pwd)/$SERVER_DIR"
echo "=========================================="

# Replace Startup Variables (Pterodactyl template variables)
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "Executing: ${MODIFIED_STARTUP}"

# Run the Server
eval "${MODIFIED_STARTUP}"
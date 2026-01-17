#!/bin/bash

# Working directory
cd /home/container || exit 1

# Set defaults for empty variables
export SCPSL_PORT=${SCPSL_PORT:-7777}

# Display startup info
echo "=========================================="
echo "  SCP:SL Server Starting"
echo "=========================================="
echo "Port: ${SCPSL_PORT}"
echo "=========================================="

# Replace Startup Variables
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "Executing: ${MODIFIED_STARTUP}"

# Run the Server
eval "${MODIFIED_STARTUP}"
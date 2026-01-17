#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "###############################################################"
echo "#           SCP:SL Server Installer (Minimal)                 #"
echo "#              With Exiled Framework Support                   #"
echo "###############################################################"

# Install dependencies
log_info "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq unzip libicu-dev lib32gcc-s1 curl ca-certificates
apt-get clean
rm -rf /var/lib/apt/lists/*
log_success "Dependencies installed"

# Clean up old installation
log_info "Cleaning old installation..."
rm -rf /mnt/server/.bin
mkdir -p /mnt/server/{.bin,.config}
log_success "Cleanup completed"

# Download SteamCMD
log_info "Downloading SteamCMD..."
mkdir -p /mnt/server/.bin/SteamCMD
cd /mnt/server/.bin/SteamCMD

if curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -; then
    chmod +x steamcmd.sh linux32/steamcmd 2>/dev/null || true
    log_success "SteamCMD downloaded"
else
    log_error "Failed to download SteamCMD"
    exit 1
fi

# Download SCP:SL Dedicated Server
log_info "Downloading SCP:SL Dedicated Server..."
log_info "Beta: ${SCPSL_BETA_NAME:-public}"

STEAMCMD_COMMAND="./steamcmd.sh +force_install_dir /mnt/server/.bin/SCPSLDS +login anonymous +app_update 996560"

if [ -n "$SCPSL_BETA_NAME" ] && [ "$SCPSL_BETA_NAME" != "public" ]; then
    STEAMCMD_COMMAND="$STEAMCMD_COMMAND -beta \"$SCPSL_BETA_NAME\""
    
    if [ -n "$SCPSL_BETA_PASS" ] && [ "$SCPSL_BETA_PASS" != "none" ]; then
        STEAMCMD_COMMAND="$STEAMCMD_COMMAND -betapassword \"$SCPSL_BETA_PASS\""
    fi
fi

STEAMCMD_COMMAND="$STEAMCMD_COMMAND validate +quit"

# Run SteamCMD with retries
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    log_info "Downloading server (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    if eval $STEAMCMD_COMMAND; then
        log_success "Server downloaded successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log_warning "Download failed, retrying in 5 seconds..."
            sleep 5
        else
            log_error "Failed to download server after $MAX_RETRIES attempts"
            exit 1
        fi
    fi
done

# Verify server installation
if [ ! -f "/mnt/server/.bin/SCPSLDS/LocalAdmin" ]; then
    log_error "Server installation failed - LocalAdmin not found"
    exit 1
fi

chmod +x /mnt/server/.bin/SCPSLDS/LocalAdmin
log_success "SCP:SL server installed"

# Install Exiled
if [ "${SCPSL_EXILED:-1}" -ne 0 ]; then
    log_info "Installing Exiled framework..."
    mkdir -p /mnt/server/.bin/ExiledInstaller
    cd /mnt/server/.bin/ExiledInstaller
    
    # Download Exiled installer
    EXILED_URL="https://github.com/Exiled-Team/EXILED/releases/latest/download/Exiled.Installer-Linux"
    
    if [ "$SCPSL_EXILED" -eq 2 ]; then
        log_info "Using Exiled pre-release version"
    else
        log_info "Using Exiled stable version"
    fi
    
    log_info "Downloading Exiled installer from: $EXILED_URL"
    if curl -L "$EXILED_URL" -o Exiled.Installer-Linux; then
        chmod +x Exiled.Installer-Linux
        
        # Build installer arguments - only use valid flags
        EXILED_ARGS="--path /mnt/server/.bin/SCPSLDS --appdata /mnt/server/.config/"
        
        if [ "$SCPSL_EXILED" -eq 2 ]; then
            EXILED_ARGS="$EXILED_ARGS --pre-releases"
        fi
        
        log_info "Running Exiled installer with arguments: $EXILED_ARGS"
        if ./Exiled.Installer-Linux $EXILED_ARGS; then
            # Verify Exiled installation
            EXILED_DLL="/mnt/server/.bin/SCPSLDS/SCPSL_Data/Managed/Assembly-CSharp.dll"
            EXILED_CONFIG="/mnt/server/.config/EXILED"
            
            if [ -f "$EXILED_DLL" ] && [ -d "$EXILED_CONFIG" ]; then
                log_success "Exiled installed successfully and verified!"
                log_info "  - Assembly-CSharp.dll found"
                log_info "  - EXILED config directory found"
            else
                log_warning "Exiled installer completed but verification failed:"
                [ ! -f "$EXILED_DLL" ] && log_warning "  - Assembly-CSharp.dll not found at $EXILED_DLL"
                [ ! -d "$EXILED_CONFIG" ] && log_warning "  - EXILED directory not found at $EXILED_CONFIG"
                log_warning "Exiled may still work, but installation may be incomplete"
            fi
        else
            log_error "Exiled installer exited with an error"
            if [ "${SCPSL_EXILED:-1}" -ne 0 ]; then
                log_error "Exiled installation is enabled but failed. Server may not function correctly."
            fi
        fi
    else
        log_error "Failed to download Exiled installer from $EXILED_URL"
        if [ "${SCPSL_EXILED:-1}" -ne 0 ]; then
            log_error "Exiled installation is enabled but download failed. Server may not function correctly."
        fi
    fi
else
    log_info "Skipping Exiled installation (disabled)"
fi

# Cleanup
log_info "Cleaning up installation files..."
rm -rf /mnt/server/.bin/SteamCMD
rm -rf /mnt/server/.bin/ExiledInstaller

# Set permissions
chown -R container:container /mnt/server 2>/dev/null || true

# Final summary
echo ""
echo "###############################################################"
log_success "Installation completed!"
echo "###############################################################"
echo ""
log_info "Installation Summary:"
echo "  • SCP:SL Server: ✓ Installed"
echo "  • Exiled: $([ "${SCPSL_EXILED:-1}" -ne 0 ] && echo '✓ Installed' || echo '✗ Skipped')"
echo ""
log_info "Server is ready to start!"
echo "###############################################################"
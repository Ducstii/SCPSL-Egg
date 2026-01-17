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
echo "#                 SCP:SL Server Installer                      #"
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
    EXILED_TEMP_DIR="/mnt/server/.bin/ExiledInstaller"
    mkdir -p "$EXILED_TEMP_DIR"
    cd "$EXILED_TEMP_DIR"
    
    # Download Exiled installer
    EXILED_URL="https://github.com/Exiled-Team/EXILED/releases/latest/download/Exiled.Installer-Linux"
    
    if [ "$SCPSL_EXILED" -eq 2 ]; then
        log_info "Using Exiled pre-release version"
    else
        log_info "Using Exiled stable version"
    fi
    
    log_info "Downloading Exiled installer from: $EXILED_URL"
    if curl -L -f "$EXILED_URL" -o Exiled.Installer-Linux; then
        chmod +x Exiled.Installer-Linux
        
        # Verify the installer was downloaded correctly (not HTML error page)
        if ! file Exiled.Installer-Linux | grep -qE "(ELF|executable|binary)"; then
            log_error "Downloaded file is not a valid executable"
            log_error "This might be a GitHub error page. Check the URL: $EXILED_URL"
            rm -f Exiled.Installer-Linux
        else
            # Build installer arguments - run from server directory
            SERVER_DIR="/mnt/server/.bin/SCPSLDS"
            APPDATA_DIR="/mnt/server/.config"
            
            # Copy installer to server directory and run from there
            cp Exiled.Installer-Linux "$SERVER_DIR/"
            cd "$SERVER_DIR"
            
            # Build installer command
            # --exiled is REQUIRED and should point to the .config directory (installer creates EXILED subfolder)
            INSTALLER_CMD="./Exiled.Installer-Linux --path \"$SERVER_DIR\" --appdata \"$APPDATA_DIR\" --exiled \"$APPDATA_DIR\""
            
            if [ "$SCPSL_EXILED" -eq 2 ]; then
                INSTALLER_CMD="$INSTALLER_CMD --pre-releases"
            fi
            
            log_info "Running Exiled installer from server directory..."
            log_info "Command: $INSTALLER_CMD"
            
            # Temporarily disable exit on error to capture installer output
            set +e
            INSTALLER_OUTPUT=$(eval $INSTALLER_CMD 2>&1)
            INSTALLER_EXIT=$?
            set -e
            
            # Show installer output
            echo "$INSTALLER_OUTPUT"
            
            # Remove installer from server directory after use
            rm -f "$SERVER_DIR/Exiled.Installer-Linux"
            
            # Verify Exiled installation regardless of exit code (installer may return non-zero even on success)
            EXILED_DLL="$SERVER_DIR/SCPSL_Data/Managed/Assembly-CSharp.dll"
            EXILED_PLUGINS_DIR="$APPDATA_DIR/SCP Secret Laboratory/LabAPI/plugins/global"
            
            if [ -f "$EXILED_DLL" ] && [ -d "$EXILED_PLUGINS_DIR" ]; then
                log_success "Exiled installed successfully and verified!"
                log_info "  - Exiled plugins directory found at $EXILED_PLUGINS_DIR"
            else
                log_warning "Exiled installation verification failed:"
                [ ! -f "$EXILED_DLL" ] && log_warning "  - Assembly-CSharp.dll not found at $EXILED_DLL"
                [ ! -d "$EXILED_PLUGINS_DIR" ] && log_warning "  - Exiled plugins directory not found at $EXILED_PLUGINS_DIR"
                
                # Check if installer gave any hints in output
                if echo "$INSTALLER_OUTPUT" | grep -qi "error\|failed\|cannot"; then
                    log_error "Installer output indicates an error occurred"
                fi
                
                log_error "Exiled installation may have failed. Please check the installer output above."
            fi
        fi
    else
        log_error "Failed to download Exiled installer from $EXILED_URL"
        log_error "This could be due to network issues or the URL being incorrect"
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
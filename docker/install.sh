#!/bin/bash

set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_info "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq unzip libicu-dev lib32gcc-s1 curl ca-certificates file
apt-get clean
rm -rf /var/lib/apt/lists/*
log_success "Dependencies installed"

log_info "Cleaning old installation..."
rm -rf /mnt/server/.bin
mkdir -p /mnt/server/{.bin,.config}
log_success "Cleanup completed"

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

if [ ! -f "/mnt/server/.bin/SCPSLDS/LocalAdmin" ]; then
    log_error "Server installation failed - LocalAdmin not found"
    exit 1
fi

chmod +x /mnt/server/.bin/SCPSLDS/LocalAdmin
log_success "SCP:SL server installed"

if [ "${SCPSL_EXILED:-1}" -ne 0 ]; then
    log_info "Installing Exiled framework..."
    EXILED_TEMP_DIR="/mnt/server/.bin/ExiledInstaller"
    mkdir -p "$EXILED_TEMP_DIR"
    cd "$EXILED_TEMP_DIR"
    
    # Get the latest release tag from GitHub API
    log_info "Fetching latest Exiled release information..."
    set +e
    API_RESPONSE=$(curl -sL "https://api.github.com/repos/ExMod-Team/EXILED/releases")
    API_EXIT=$?
    set -e
    
    if [ $API_EXIT -ne 0 ] || [ -z "$API_RESPONSE" ]; then
        log_error "Failed to fetch Exiled releases from GitHub API (exit code: $API_EXIT)"
        log_error "API response: ${API_RESPONSE:0:200}"
        EXILED_RELEASE_TAG=""
    else
        if [ "$SCPSL_EXILED" -eq 2 ]; then
            log_info "Using Exiled pre-release version"
            # For pre-releases, get the latest release (which may include pre-releases)
            EXILED_RELEASE_TAG=$(echo "$API_RESPONSE" | grep -oP '"tag_name":\s*"\K[^"]+' 2>/dev/null | head -1)
            # Fallback if grep -P not available
            if [ -z "$EXILED_RELEASE_TAG" ]; then
                EXILED_RELEASE_TAG=$(echo "$API_RESPONSE" | grep '"tag_name"' | head -1 | sed -n 's/.*"tag_name":\s*"\([^"]*\)".*/\1/p')
            fi
        else
            log_info "Using Exiled stable version"
            # For stable releases, get the latest non-prerelease
            EXILED_RELEASE_TAG=$(echo "$API_RESPONSE" | grep -oP '"tag_name":\s*"\K[^"]+' 2>/dev/null | grep -vE "(alpha|beta|rc)" | head -1)
            # Fallback if grep -P not available
            if [ -z "$EXILED_RELEASE_TAG" ]; then
                EXILED_RELEASE_TAG=$(echo "$API_RESPONSE" | grep '"tag_name"' | grep -vE "(alpha|beta|rc)" | head -1 | sed -n 's/.*"tag_name":\s*"\([^"]*\)".*/\1/p')
            fi
            # Fallback to any latest release if no stable found
            if [ -z "$EXILED_RELEASE_TAG" ]; then
                log_warning "No stable release found, falling back to latest release"
                EXILED_RELEASE_TAG=$(echo "$API_RESPONSE" | grep -oP '"tag_name":\s*"\K[^"]+' 2>/dev/null | head -1)
                if [ -z "$EXILED_RELEASE_TAG" ]; then
                    EXILED_RELEASE_TAG=$(echo "$API_RESPONSE" | grep '"tag_name"' | head -1 | sed -n 's/.*"tag_name":\s*"\([^"]*\)".*/\1/p')
                fi
            fi
        fi
    fi
    
    if [ -z "$EXILED_RELEASE_TAG" ]; then
        log_error "Failed to extract Exiled release tag from API response"
        log_error "API response preview: ${API_RESPONSE:0:500}"
        log_error "This could be due to network issues, API rate limiting, or unexpected API response format"
    else
        EXILED_URL="https://github.com/ExMod-Team/EXILED/releases/download/${EXILED_RELEASE_TAG}/Exiled.Installer-Linux"
        log_info "Latest release tag: $EXILED_RELEASE_TAG"
        log_info "Downloading Exiled installer from: $EXILED_URL"
        
        if curl -L -f "$EXILED_URL" -o Exiled.Installer-Linux; then
            chmod +x Exiled.Installer-Linux
            
            # Verify the downloaded file is an executable
            FILE_CHECK=$(file Exiled.Installer-Linux 2>/dev/null || echo "")
            if [ -z "$FILE_CHECK" ]; then
                log_warning "Unable to verify file type (file command failed), proceeding anyway"
            elif ! echo "$FILE_CHECK" | grep -qE "(ELF|executable|binary)"; then
                log_error "Downloaded file is not a valid executable"
                log_error "File type: $FILE_CHECK"
                log_error "This might be a GitHub error page. Check the URL: $EXILED_URL"
                rm -f Exiled.Installer-Linux
            else
                SERVER_DIR="/mnt/server/.bin/SCPSLDS"
                APPDATA_DIR="/mnt/server/.config"
                
                cp Exiled.Installer-Linux "$SERVER_DIR/"
                cd "$SERVER_DIR"
                
                # Build installer command with required flags
                INSTALLER_CMD="./Exiled.Installer-Linux --path \"$SERVER_DIR\" --appdata \"$APPDATA_DIR\" --exiled \"$APPDATA_DIR\" --exit --skip-version-select"
                
                # Add pre-releases flag if requested
                if [ "$SCPSL_EXILED" -eq 2 ]; then
                    INSTALLER_CMD="$INSTALLER_CMD --pre-releases"
                fi
                
                log_info "Running Exiled installer from server directory..."
                log_info "Command: $INSTALLER_CMD"
            
            set +e
            INSTALLER_OUTPUT=$(eval $INSTALLER_CMD 2>&1)
            INSTALLER_EXIT=$?
            set -e
            
            echo "$INSTALLER_OUTPUT"
            
            rm -f "$SERVER_DIR/Exiled.Installer-Linux"
            
            # Check if installer failed
            if [ $INSTALLER_EXIT -ne 0 ]; then
                log_error "Exiled installer exited with error code: $INSTALLER_EXIT"
                log_error "Please check the installer output above for details"
            else
                # Verify installation by checking for expected files
                EXILED_DLL="$SERVER_DIR/SCPSL_Data/Managed/Assembly-CSharp.dll"
                EXILED_PLUGINS_DIR="$APPDATA_DIR/SCP Secret Laboratory/LabAPI/plugins/global"
                
                # Check for installation completion message
                if echo "$INSTALLER_OUTPUT" | grep -qi "Installation complete"; then
                    log_success "Exiled installed successfully!"
                    
                    # Additional verification if files exist
                    if [ -f "$EXILED_DLL" ]; then
                        log_info "  - Assembly-CSharp.dll found at $EXILED_DLL"
                    fi
                    
                    if [ -d "$EXILED_PLUGINS_DIR" ]; then
                        log_info "  - Exiled plugins directory found at $EXILED_PLUGINS_DIR"
                    else
                        log_warning "  - Exiled plugins directory not found at $EXILED_PLUGINS_DIR (may be normal depending on installation path)"
                    fi
                else
                    log_warning "Exiled installation verification incomplete:"
                    [ ! -f "$EXILED_DLL" ] && log_warning "  - Assembly-CSharp.dll not found at $EXILED_DLL"
                    [ ! -d "$EXILED_PLUGINS_DIR" ] && log_warning "  - Exiled plugins directory not found at $EXILED_PLUGINS_DIR"
                    
                    if echo "$INSTALLER_OUTPUT" | grep -qi "error\|failed\|cannot\|exception"; then
                        log_error "Installer output indicates an error occurred"
                    fi
                    
                    log_warning "Please check the installer output above to verify installation"
                fi
            fi
        fi
        else
            log_error "Failed to download Exiled installer from $EXILED_URL"
            log_error "This could be due to network issues or the URL being incorrect"
        fi
    fi
else
    log_info "Skipping Exiled installation (disabled)"
fi

log_info "Cleaning up installation files..."
rm -rf /mnt/server/.bin/SteamCMD
rm -rf /mnt/server/.bin/ExiledInstaller

chown -R container:container /mnt/server 2>/dev/null || true

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

# If entrypoint script exists and we're not in installation-only mode, start the server
if [ "${INSTALL_ONLY:-0}" -ne 1 ]; then
    if [ -f "/entrypoint.sh" ]; then
        echo ""
        log_info "Starting server using entrypoint script..."
        echo ""
        exec /entrypoint.sh
    elif [ -f "/home/container/entrypoint.sh" ]; then
        echo ""
        log_info "Starting server using entrypoint script..."
        echo ""
        exec /home/container/entrypoint.sh
    elif [ -f "/mnt/server/.bin/SCPSLDS/LocalAdmin" ]; then
        # Entrypoint not available, start server directly
        echo ""
        log_info "Starting server directly..."
        echo ""
        cd /mnt/server/.bin/SCPSLDS || exit 1
        export SCPSL_PORT=${SCPSL_PORT:-7777}
        exec ./LocalAdmin "${SCPSL_PORT}"
    else
        echo ""
        log_info "Installation complete. Server will start when container is started."
        echo ""
    fi
else
    echo ""
    log_info "Installation complete. Server will start when container is started."
    echo ""
fi
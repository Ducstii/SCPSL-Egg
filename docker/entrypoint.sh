#!/bin/bash
# SCPSL-Egg — https://github.com/Ducstii/SCPSL-Egg · ducstii

set -euo pipefail

# shellcheck source=paths.inc.sh
source /paths.inc.sh

readonly AUTHOR="ducstii"
readonly REPO_URL="https://github.com/Ducstii/SCPSL-Egg"

if [[ -t 1 ]]; then
    G='\033[0;32m'
    C='\033[0;36m'
    Y='\033[1;33m'
    R='\033[0;31m'
    DIM='\033[2m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    G= C= Y= R= DIM= BOLD= NC=
fi

log() { echo -e "${C}·${NC} $*"; }
warn() { echo -e "${Y}!${NC} $*"; }
err() { echo -e "${R}✗${NC} $*" >&2; }

export SCPSL_PORT="${SCPSL_PORT:-7777}"
SERVER_DIR=""

banner() {
    echo ""
    echo -e "${G}╭${NC}${DIM}────────────────────────────────────────────────────────────${NC}${G}╮${NC}"
    echo -e "${G}│${NC}  ${BOLD}SCP: Secret Laboratory${NC}  ${DIM}· server process${NC}"
    echo -e "${G}│${NC}  ${DIM}${BOLD}${AUTHOR}${NC}${DIM}  ·  ${REPO_URL}${NC}"
    echo -e "${G}╰${NC}${DIM}────────────────────────────────────────────────────────────${NC}${G}╯${NC}"
    echo ""
}

try_layout() {
    local base="$1"
    local rel="$2"
    local label="$3"
    if [[ -d "${base}/${rel}" ]]; then
        cd "${base}" || exit 1
        SERVER_DIR="${rel}"
        log "Data root: ${BOLD}${label}${NC}"
        return 0
    fi
    return 1
}

resolve_server_home() {
    if try_layout /mnt/server "${PD_GAME_REL}" "/mnt/server"; then
        return 0
    fi
    if try_layout /mnt/server "${PD_LEGACY_REL}" "/mnt/server"; then
        warn "Legacy layout detected — run a fresh install from the panel to move to the current paths."
        return 0
    fi
    if try_layout /home/container "${PD_GAME_REL}" "/home/container"; then
        return 0
    fi
    if try_layout /home/container "${PD_LEGACY_REL}" "/home/container"; then
        warn "Legacy layout detected — reinstall from the panel to migrate."
        return 0
    fi
    if try_layout . "${PD_GAME_REL}" "$(pwd)"; then
        return 0
    fi
    if try_layout . "${PD_LEGACY_REL}" "$(pwd)"; then
        warn "Legacy layout detected — reinstall from the panel to migrate."
        return 0
    fi
    err "Could not find ${BOLD}${PD_GAME_REL}${NC} (or legacy ${PD_LEGACY_REL})."
    err "Install from the panel first, or check volume mounts."
    exit 1
}

banner
log "Listening port: ${BOLD}${SCPSL_PORT}${NC}"
resolve_server_home

if [[ ! -f "${SERVER_DIR}/LocalAdmin" ]]; then
    err "Missing ${SERVER_DIR}/LocalAdmin — installation looks incomplete."
    exit 1
fi
chmod +x "${SERVER_DIR}/LocalAdmin" 2>/dev/null || true
log "Executable: ${BOLD}$(pwd)/${SERVER_DIR}/LocalAdmin${NC}"

hr="${DIM}────────────────────────────────────────────────────────────${NC}"
echo -e "$hr"

if [[ -z "${STARTUP:-}" ]]; then
    warn "STARTUP is empty — running LocalAdmin with SCPSL_PORT."
    cd "${SERVER_DIR}" || exit 1
    exec ./LocalAdmin "${SCPSL_PORT}"
fi

log "Panel STARTUP:"
echo -e "${DIM}${STARTUP}${NC}"

# Pterodactyl: {{VAR}} → shell parameter expansion (same idea as stock eggs)
MODIFIED_STARTUP=$(sed -e 's/{{/${/g' -e 's/}}/}/g' <<<"${STARTUP}")
echo -e "${DIM}→ ${MODIFIED_STARTUP}${NC}"
echo -e "$hr"

eval "${MODIFIED_STARTUP}"

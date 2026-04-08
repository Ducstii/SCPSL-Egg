#!/bin/bash
# SCPSL-Egg install — https://github.com/Ducstii/SCPSL-Egg · ducstii

set -euo pipefail

readonly AUTHOR="ducstii"
readonly REPO_URL="https://github.com/Ducstii/SCPSL-Egg"
readonly STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
readonly STEAMCMD_FALLBACK="https://media.steampowered.com/client/installer/steamcmd_linux.tar.gz"
readonly SCPSL_APP_ID="996560"
readonly EXILED_API="https://api.github.com/repos/ExMod-Team/EXILED/releases"

# Paths: must match docker/paths.inc.sh (install is curl’d standalone — no source).
readonly PD_GAME_REL="server"
readonly PD_DATA_REL="appdata"
readonly PD_WORK_REL="tmp"
readonly PD_LEGACY_REL=".bin/SCPSLDS"
readonly SRV="/mnt/server"
readonly PD_GAME_ABS="${SRV}/${PD_GAME_REL}"
readonly PD_DATA_ABS="${SRV}/${PD_DATA_REL}"
readonly PD_WORK_ABS="${SRV}/${PD_WORK_REL}"

# ── ANSI (disabled when stdout is not a TTY — cleaner in raw panel logs) ─────
if [[ -t 1 ]]; then
    R='\033[0;31m'
    G='\033[0;32m'
    Y='\033[1;33m'
    C='\033[0;36m'
    DIM='\033[2m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    R= G= Y= C= DIM= BOLD= NC=
fi

log_info()    { echo -e "${C}·${NC} $*"; }
log_ok()      { echo -e "${G}✓${NC} $*"; }
log_warn()    { echo -e "${Y}!${NC} $*"; }
log_err()     { echo -e "${R}✗${NC} $*" >&2; }

banner_top() {
    echo ""
    echo -e "${C}╭${NC}${DIM}────────────────────────────────────────────────────────────${NC}${C}╮${NC}"
    echo -e "${C}│${NC}  ${BOLD}SCP: Secret Laboratory${NC}  ${DIM}· dedicated server installer${NC}"
    echo -e "${C}│${NC}  ${DIM}${BOLD}${AUTHOR}${NC}${DIM}  ·  ${REPO_URL}${NC}"
    echo -e "${C}╰${NC}${DIM}────────────────────────────────────────────────────────────${NC}${C}╯${NC}"
    echo ""
}

banner_done() {
    echo ""
    echo -e "${G}╭${NC}${DIM}────────────────────────────────────────────────────────────${NC}${G}╮${NC}"
    echo -e "${G}│${NC}  ${BOLD}Install finished${NC}  ${DIM}— start the server from the panel when you are ready.${NC}"
    echo -e "${G}╰${NC}${DIM}────────────────────────────────────────────────────────────${NC}${G}╯${NC}"
    echo ""
}

phase() {
    # $1 = title, $2 = step id e.g. 1/5
    echo -e "\n${DIM}[${2}]${NC} ${BOLD}${1}${NC}"
}

hr() { echo -e "${DIM}────────────────────────────────────────────────────────────${NC}"; }

exiled_release_tag() {
    local mode="$1" json="$2"
    if ! command -v jq &>/dev/null; then
        log_err "jq missing — dependency install failed?"
        return 1
    fi
    if [[ "$mode" == "2" ]]; then
        jq -r '.[0].tag_name // empty' <<<"$json"
    else
        jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name // empty' <<<"$json"
    fi
}

fetch_exiled_tag() {
    local mode="${SCPSL_EXILED:-1}"
    local hdr=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
    [[ -n "${GITHUB_TOKEN:-}" ]] && hdr+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

    local json
    json=$(curl -fsSL "${hdr[@]}" "$EXILED_API" 2>/dev/null) || true
    if [[ -z "$json" ]] || ! echo "$json" | jq -e . &>/dev/null; then
        log_warn "First GitHub request failed or was not JSON. Retrying without a token…"
        json=$(curl -fsSL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$EXILED_API" 2>/dev/null) || true
    fi

    if [[ -z "$json" ]]; then
        log_err "Empty response from GitHub (network or firewall)."
        return 1
    fi

    if echo "$json" | jq -e 'type == "object" and (.message | type == "string")' &>/dev/null; then
        log_err "GitHub API: $(echo "$json" | jq -r '.message')"
        return 1
    fi

    if ! echo "$json" | jq -e 'type == "array"' &>/dev/null; then
        log_err "Unexpected GitHub response shape (expected a releases array)."
        return 1
    fi

    local tag
    tag=$(exiled_release_tag "$mode" "$json")
    if [[ -z "$tag" && "$mode" != "2" ]]; then
        log_warn "No stable (non-prerelease) release; using newest entry in the feed."
        tag=$(echo "$json" | jq -r '.[0].tag_name // empty')
    fi

    if [[ -z "$tag" ]]; then
        log_err "Could not resolve an Exiled release tag."
        return 1
    fi

    printf '%s\n' "$tag"
    return 0
}

download_steamcmd() {
    local dest="$1"
    mkdir -p "$dest"
    cd "$dest"
    if curl -fsSL --retry 3 --retry-delay 2 "$STEAMCMD_URL" | tar zxf -; then
        chmod +x steamcmd.sh linux32/steamcmd 2>/dev/null || true
        return 0
    fi
    log_warn "Primary CDN failed; trying alternate mirror…"
    if curl -fsSL --retry 3 --retry-delay 2 "$STEAMCMD_FALLBACK" | tar zxf -; then
        chmod +x steamcmd.sh linux32/steamcmd 2>/dev/null || true
        return 0
    fi
    return 1
}

run_steamcmd_install() {
    local steamdir="$1"
    cd "$steamdir"
    local -a args=(
        +force_install_dir "$PD_GAME_ABS"
        +login anonymous
        +app_update "$SCPSL_APP_ID"
    )
    if [[ -n "${SCPSL_BETA_NAME:-}" && "$SCPSL_BETA_NAME" != "public" ]]; then
        args+=( -beta "$SCPSL_BETA_NAME" )
        if [[ -n "${SCPSL_BETA_PASS:-}" && "$SCPSL_BETA_PASS" != "none" ]]; then
            args+=( -betapassword "$SCPSL_BETA_PASS" )
        fi
    fi
    args+=( validate +quit )
    ./steamcmd.sh "${args[@]}"
}

ensure_container_user() {
    if id -u container &>/dev/null; then
        return 0
    fi
    if useradd -m -d /home/container -s /bin/bash container 2>/dev/null; then
        return 0
    fi
    log_warn "Could not create user 'container'; leaving file ownership unchanged."
    return 1
}

# ── main ──────────────────────────────────────────────────────────────────────
banner_top

phase "Dependencies" "1/5"
apt-get update -qq
apt-get install -y -qq unzip libicu-dev lib32gcc-s1 curl ca-certificates file jq
apt-get clean
rm -rf /var/lib/apt/lists/*
log_ok "Packages ready (incl. jq for release metadata)."

hr
phase "Prepare server directory" "2/5"
log_info "Resetting server, appdata, tmp, and old layouts…"
rm -rf "${PD_GAME_ABS}" "${PD_DATA_ABS}" "${PD_WORK_ABS}" "${SRV}/.bin" "${SRV}/.local/srv-7a4e2f"
mkdir -p "${PD_GAME_ABS}" "${PD_DATA_ABS}" "${PD_WORK_ABS}"
log_ok "Directories ready: ${PD_GAME_REL}, ${PD_DATA_REL}, ${PD_WORK_REL}."

hr
phase "Steam update client" "3/5"
log_info "Fetching Steam update client (may take a moment)…"
if ! download_steamcmd "${PD_WORK_ABS}"; then
    log_err "Download of the Steam client tools failed from all mirrors."
    exit 1
fi
log_ok "Steam tools unpacked into workspace."

hr
phase "Game server files" "4/5"
log_info "App ${SCPSL_APP_ID} · branch ${SCPSL_BETA_NAME:-public}"

retries=3
attempt=1
while [[ $attempt -le $retries ]]; do
    log_info "Content download (attempt ${attempt}/${retries})…"
    if run_steamcmd_install "${PD_WORK_ABS}"; then
        log_ok "Game server files downloaded."
        break
    fi
    if [[ $attempt -eq $retries ]]; then
        log_err "Steam update could not finish after ${retries} attempts."
        exit 1
    fi
    log_warn "Steam update failed — waiting 8s before retry…"
    sleep 8
    attempt=$((attempt + 1))
done

if [[ ! -f "${PD_GAME_ABS}/LocalAdmin" ]]; then
    log_err "LocalAdmin missing under ${PD_GAME_REL} — install incomplete."
    exit 1
fi
chmod +x "${PD_GAME_ABS}/LocalAdmin"

hr
phase "Exiled (optional)" "5/5"
if [[ "${SCPSL_EXILED:-1}" -eq 0 ]]; then
    log_info "Exiled disabled (SCPSL_EXILED=0) — skipping."
else
    if [[ "${SCPSL_EXILED:-1}" -eq 2 ]]; then
        log_info "Exiled channel: ${BOLD}pre-release${NC}"
    else
        log_info "Exiled channel: ${BOLD}stable${NC}"
    fi

    EXILED_RELEASE_TAG=""
    if ! EXILED_RELEASE_TAG="$(fetch_exiled_tag)"; then
        EXILED_RELEASE_TAG=""
    fi

    if [[ -z "$EXILED_RELEASE_TAG" ]]; then
        log_warn "Skipping Exiled — fix network or set GITHUB_TOKEN if you hit API rate limits."
    else
        EXILED_URL="https://github.com/ExMod-Team/EXILED/releases/download/${EXILED_RELEASE_TAG}/Exiled.Installer-Linux"
        log_info "Release ${BOLD}${EXILED_RELEASE_TAG}${NC}"
        mkdir -p "${PD_WORK_ABS}"
        cd "${PD_WORK_ABS}"

        if curl -fsSL --retry 3 --retry-delay 2 -o Exiled.Installer-Linux "$EXILED_URL"; then
            chmod +x Exiled.Installer-Linux
            ft="$(file -b Exiled.Installer-Linux 2>/dev/null || true)"
            if [[ -n "$ft" ]] && ! grep -qE 'ELF|executable|binary' <<<"$ft"; then
                log_err "Download is not a Linux binary (got: ${ft:0:80}…)"
                rm -f Exiled.Installer-Linux
            else
                SERVER_DIR="${PD_GAME_ABS}"
                APPDATA_DIR="${PD_DATA_ABS}"
                cp -f Exiled.Installer-Linux "$SERVER_DIR/"
                cd "$SERVER_DIR"

                set +e
                if [[ "${SCPSL_EXILED:-1}" -eq 2 ]]; then
                    INSTALLER_OUTPUT="$(./Exiled.Installer-Linux \
                        --path "$SERVER_DIR" \
                        --appdata "$APPDATA_DIR" \
                        --exiled "$APPDATA_DIR" \
                        --exit --skip-version-select --pre-releases 2>&1)"
                else
                    INSTALLER_OUTPUT="$(./Exiled.Installer-Linux \
                        --path "$SERVER_DIR" \
                        --appdata "$APPDATA_DIR" \
                        --exiled "$APPDATA_DIR" \
                        --exit --skip-version-select 2>&1)"
                fi
                INSTALLER_EXIT=$?
                set -e

                printf '%s\n' "$INSTALLER_OUTPUT"
                rm -f "$SERVER_DIR/Exiled.Installer-Linux"

                if [[ $INSTALLER_EXIT -ne 0 ]]; then
                    log_err "Exiled installer exited with code ${INSTALLER_EXIT}."
                elif grep -qi 'Installation complete' <<<"$INSTALLER_OUTPUT"; then
                    log_ok "Exiled installed."
                else
                    log_warn "Exiled finished without a clear success string — check output above."
                fi
            fi
        else
            log_err "Could not download Exiled installer."
        fi
    fi
fi

hr
log_info "Removing workspace scratch dir (${PD_WORK_REL})…"
rm -rf "${PD_WORK_ABS}"

if ensure_container_user; then
    chown -R container:container /mnt/server
    log_ok "Ownership set to user ${BOLD}container${NC} (matches game container)."
fi

banner_done
echo -e "  ${DIM}SCP:SL${NC}     ${G}installed${NC}"
if [[ "${SCPSL_EXILED:-1}" -eq 0 ]]; then
    echo -e "  ${DIM}Exiled${NC}     ${Y}skipped${NC}"
else
    echo -e "  ${DIM}Exiled${NC}     ${G}attempted (see logs above)${NC}"
fi
echo ""

# Post-install: panel usually does not chain into game image entrypoint from ubuntu installer.
if [[ "${INSTALL_ONLY:-0}" != "1" ]]; then
    if [[ -f /entrypoint.sh ]]; then
        log_info "Handing off to ${BOLD}/entrypoint.sh${NC}…"
        exec /entrypoint.sh
    fi
    if [[ -f /home/container/entrypoint.sh ]]; then
        log_info "Handing off to entrypoint…"
        exec /home/container/entrypoint.sh
    fi
    if [[ -f "${PD_GAME_ABS}/LocalAdmin" ]]; then
        log_info "Starting LocalAdmin directly (no entrypoint in this environment)…"
        cd "${PD_GAME_ABS}" || exit 1
        export SCPSL_PORT="${SCPSL_PORT:-7777}"
        exec ./LocalAdmin "${SCPSL_PORT}"
    fi
fi
log_info "Install only — start the server from the panel when ready."

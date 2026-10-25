#!/bin/bash
#
# reactive-dfr — universal install script (no PKGBUILD needed)
#
# Compiles the Rust daemon, installs the Python context daemon,
# shared assets, config, systemd services, udev rules, and deploys
# user-level config + widgets to ~/.config/reactive-dfr/.
#
# Works on any Linux distro that has:
#   - rust/cargo, dkms (for appletbdrm-t1), python3, build libs
#
# Usage:
#   sudo ./install.sh install     # build + install everything + deploy user config
#   sudo ./install.sh uninstall   # remove everything
#   ./install.sh status           # show installation status
#   ./install.sh setup            # deploy user config only (run as your user, not root)
#
# After install: reboot to activate the Touch Bar.
# Requires appletbdrm-t1 to be installed first (the kernel driver).

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install destinations
BIN_DIR="/usr/bin"
SHARE_DIR="/usr/share/reactive-dfr"
LIB_DIR="/usr/lib/reactive-dfr/context-daemon"
ETC_CONFIG_DIR="/etc/reactive-dfr/config"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
SYSTEMD_USER_DIR="/usr/lib/systemd/user"
UDEV_DIR="/etc/udev/rules.d"

# User config destination (resolved at deploy time)
USER_CONFIG_DIR=""
USER_WIDGETS_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BLUE}=== $* ===${NC}"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Run as root: sudo ./install.sh install"
    fi
}

get_target_user() {
    # When running under sudo, SUDO_USER is the real user.
    # Otherwise fall back to the current user.
    echo "${SUDO_USER:-$USER}"
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

check_deps() {
    info "Checking dependencies..."
    local missing=()

    command -v cargo >/dev/null 2>&1 || missing+=("rust/cargo")
    command -v gcc     >/dev/null 2>&1 || missing+=("gcc")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v pkg-config >/dev/null 2>&1 || missing+=("pkgconf")

    # Build libraries (checked via pkg-config)
    pkg-config --exists cairo    2>/dev/null || missing+=("cairo (dev)")
    pkg-config --exists pango   2>/dev/null || missing+=("pango (dev)")
    pkg-config --exists librsvg-2.0 2>/dev/null || missing+=("librsvg (dev)")
    pkg-config --exists libdrm   2>/dev/null || missing+=("libdrm (dev)")
    pkg-config --exists libinput 2>/dev/null || missing+=("libinput (dev)")

    # Python runtime dep
    python3 -c "import tomli_w" 2>/dev/null || missing+=("python-tomli-w")

    # Kernel headers (for appletbdrm-t1, not us — but the driver is required)
    local kbuild="/lib/modules/$(uname -r)/build"
    if [ ! -d "$kbuild" ]; then
        warn "Kernel headers not found for $(uname -r) — appletbdrm-t1 needs them"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing: ${missing[*]}\n\nInstall them first, e.g.:\n  Arch:   sudo pacman -S rust cairo pango librsvg libdrm libinput pkgconf python-tomli-w wl-clipboard\n  Debian: sudo apt install cargo build-essential libcairo2-dev libpango1.0-dev librsvg2-dev libdrm-dev libinput-dev pkg-config python3-tomli-w wl-clipboard\n  Fedora: sudo dnf install cargo gcc cairo-devel pango-devel librsvg2-devel libdrm-devel libinput-devel pkgconf python3-tomli-w wl-clipboard"
    fi

    # Check that appletbdrm-t1 is installed (the kernel driver)
    if ! lsmod 2>/dev/null | grep -q appletbdrm; then
        if ! dkms status appletbdrm 2>/dev/null | grep -q installed; then
            warn "appletbdrm-t1 driver not detected — install it first or the Touch Bar won't work"
        fi
    fi

    info "All dependencies satisfied"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

do_build() {
    step "Building reactive-dfr daemon (Rust)"

    cd "${SCRIPT_DIR}/daemon"
    info "Running cargo build --release..."
    cargo build --release

    local binary="target/release/reactive-dfr"
    if [ ! -f "$binary" ]; then
        error "Build failed: ${binary} not found"
    fi

    info "Build successful: $(ls -la "$binary" | awk '{print $5}') bytes"
    cd "${SCRIPT_DIR}"
}

# ---------------------------------------------------------------------------
# Install (system-level)
# ---------------------------------------------------------------------------

install_binary() {
    step "Daemon binary"
    info "Installing reactive-dfr → ${BIN_DIR}/"
    install -Dm755 "${SCRIPT_DIR}/daemon/target/release/reactive-dfr" \
        "${BIN_DIR}/reactive-dfr"
}

install_shared_assets() {
    step "Shared assets (SVG icons, default config, shipped widgets)"
    info "Installing to ${SHARE_DIR}/"
    mkdir -p "${SHARE_DIR}"
    cp -r "${SCRIPT_DIR}"/daemon/share/reactive-dfr/* "${SHARE_DIR}/"
}

install_context_daemon() {
    step "Context daemon (Python)"

    info "Installing Python scripts → ${LIB_DIR}/"
    mkdir -p "${LIB_DIR}/backends" "${LIB_DIR}/scripts" "${LIB_DIR}/widgets"

    install -Dm755 "${SCRIPT_DIR}/context-daemon/daemon.py"   "${LIB_DIR}/daemon.py"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/composer.py" "${LIB_DIR}/composer.py"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/matcher.py"  "${LIB_DIR}/matcher.py"

    install -Dm644 "${SCRIPT_DIR}/context-daemon/backends/__init__.py" "${LIB_DIR}/backends/__init__.py"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/backends/base.py"      "${LIB_DIR}/backends/base.py"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/backends/hyprland.py"  "${LIB_DIR}/backends/hyprland.py"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/backends/sway.py"      "${LIB_DIR}/backends/sway.py"

    install -Dm644 "${SCRIPT_DIR}/context-daemon/scripts/power_monitor.py" \
        "${LIB_DIR}/scripts/power_monitor.py"

    # Widgets that ship with the project (user copies them to ~/.config on setup)
    for f in "${SCRIPT_DIR}/context-daemon/widgets/"*; do
        [ -f "$f" ] && install -Dm644 "$f" "${LIB_DIR}/widgets/$(basename "$f")"
    done
}

install_config() {
    step "System config (base.toml, matcher.toml, contexts)"

    info "Installing to ${ETC_CONFIG_DIR}/"
    mkdir -p "${ETC_CONFIG_DIR}/contexts"

    install -Dm644 "${SCRIPT_DIR}/context-daemon/config/base.toml"    "${ETC_CONFIG_DIR}/base.toml"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/config/matcher.toml" "${ETC_CONFIG_DIR}/matcher.toml"
    cp "${SCRIPT_DIR}/context-daemon/config/contexts/"*.toml "${ETC_CONFIG_DIR}/contexts/"
}

install_systemd_units() {
    step "Systemd services"

    # System service (render daemon — runs as root, drops privileges)
    info "Installing reactive-dfr.service → ${SYSTEMD_SYSTEM_DIR}/"
    install -Dm644 "${SCRIPT_DIR}/daemon/etc/systemd/system/reactive-dfr.service" \
        "${SYSTEMD_SYSTEM_DIR}/reactive-dfr.service"

    # Backlight drop-in (prevent systemd-backlight from fighting the daemon)
    info "Installing backlight drop-in → ${SYSTEMD_SYSTEM_DIR}/"
    install -Dm644 "${SCRIPT_DIR}/daemon/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service" \
        "${SYSTEMD_SYSTEM_DIR}/systemd-backlight@backlight:appletb_backlight.service"

    # User services (context daemon + power monitor — available to all users)
    info "Installing user services → ${SYSTEMD_USER_DIR}/"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/systemd/touchbar-ctx.service" \
        "${SYSTEMD_USER_DIR}/touchbar-ctx.service"
    install -Dm644 "${SCRIPT_DIR}/context-daemon/systemd/touchbar-power-monitor.service" \
        "${SYSTEMD_USER_DIR}/touchbar-power-monitor.service"

    systemctl daemon-reload
    info "System services installed (enable reactive-dfr.service)"

    # Enable the system service
    systemctl enable reactive-dfr.service
    info "Enabled reactive-dfr.service"
}

install_udev_rules() {
    step "Udev rules"

    info "Installing udev rules → ${UDEV_DIR}/"
    install -Dm644 "${SCRIPT_DIR}/daemon/etc/udev/rules.d/99-touchbar-reactive-dfr.rules" \
        "${UDEV_DIR}/99-touchbar-reactive-dfr.rules"
    install -Dm644 "${SCRIPT_DIR}/daemon/etc/udev/rules.d/99-touchbar-seat.rules" \
        "${UDEV_DIR}/99-touchbar-seat.rules"

    udevadm control --reload-rules 2>/dev/null || warn "udevadm reload failed (may need reboot)"
}

# ---------------------------------------------------------------------------
# Deploy user config
# ---------------------------------------------------------------------------

deploy_user_config() {
    step "User config deployment"

    local target_user
    target_user="$(get_target_user)"
    local home_dir
    home_dir="$(getent passwd "$target_user" | cut -d: -f6)"

    if [ -z "$home_dir" ] || [ ! -d "$home_dir" ]; then
        error "Cannot find home directory for user '${target_user}'"
    fi

    USER_CONFIG_DIR="${home_dir}/.config/reactive-dfr"
    USER_WIDGETS_DIR="${USER_CONFIG_DIR}/widgets"

    info "Deploying to ${USER_CONFIG_DIR}/ for user '${target_user}'"

    mkdir -p "${USER_CONFIG_DIR}/contexts" "${USER_WIDGETS_DIR}" "${USER_CONFIG_DIR}/state"

    # Copy config from /etc if not already present (don't overwrite personal customizations)
    for f in base.toml matcher.toml; do
        if [ ! -f "${USER_CONFIG_DIR}/${f}" ]; then
            cp "${ETC_CONFIG_DIR}/${f}" "${USER_CONFIG_DIR}/${f}"
            info "  Copied: ${f}"
        else
            warn "  Exists, not overwritten: ${f}"
        fi
    done

    # Copy context configs (don't overwrite)
    for f in "${ETC_CONFIG_DIR}/contexts/"*.toml; do
        local name="$(basename "$f")"
        if [ ! -f "${USER_CONFIG_DIR}/contexts/${name}" ]; then
            cp "$f" "${USER_CONFIG_DIR}/contexts/${name}"
            info "  Copied: contexts/${name}"
        else
            warn "  Exists, not overwritten: contexts/${name}"
        fi
    done

    # Copy widgets from the installed lib dir (don't overwrite personal widgets)
    for f in "${LIB_DIR}/widgets/"*; do
        [ -f "$f" ] || continue
        local name="$(basename "$f")"
        # Skip templates — they go to the config dir, not widgets
        case "$name" in
            *.template) continue ;;
        esac
        if [ ! -f "${USER_WIDGETS_DIR}/${name}" ]; then
            cp "$f" "${USER_WIDGETS_DIR}/${name}"
            chmod +x "${USER_WIDGETS_DIR}/${name}" 2>/dev/null || true
            info "  Copied: widgets/${name}"
        else
            warn "  Exists, not overwritten: widgets/${name}"
        fi
    done

    # Feeder config from template (only if not already present)
    if [ ! -f "${USER_CONFIG_DIR}/feeder_config.toml" ]; then
        if [ -f "${LIB_DIR}/widgets/feeder_config.toml.template" ]; then
            cp "${LIB_DIR}/widgets/feeder_config.toml.template" \
               "${USER_CONFIG_DIR}/feeder_config.toml"
            info "  Copied: feeder_config.toml (from template — edit to customize)"
        fi
    else
        warn "  Exists, not overwritten: feeder_config.toml"
    fi

    # Set ownership to the target user
    chown -R "$target_user:$target_user" "${USER_CONFIG_DIR}"

    info "User config deployed. Enable user services with:"
    echo "  systemctl --user enable --now touchbar-ctx.service"
    echo "  systemctl --user enable --now touchbar-power-monitor.service"

    # Try to enable user services if the user session is available
    local uid
    uid="$(id -u "$target_user")"
    local runtime="/run/user/${uid}"
    if [ -d "$runtime" ]; then
        info "Enabling user services..."
        runuser -u "$target_user" -- env \
            XDG_RUNTIME_DIR="$runtime" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
            systemctl --user daemon-reload 2>/dev/null || true
        runuser -u "$target_user" -- env \
            XDG_RUNTIME_DIR="$runtime" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
            systemctl --user enable --now touchbar-ctx.service 2>/dev/null || \
            warn "Could not enable touchbar-ctx.service (user session may not be ready)"
        runuser -u "$target_user" -- env \
            XDG_RUNTIME_DIR="$runtime" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
            systemctl --user enable --now touchbar-power-monitor.service 2>/dev/null || \
            warn "Could not enable touchbar-power-monitor.service"
    else
        warn "User session not available — enable user services manually after login"
    fi
}

# ---------------------------------------------------------------------------
# Install (main)
# ---------------------------------------------------------------------------

do_install() {
    check_root
    check_deps

    echo -e "\n${BLUE}reactive-dfr — installation${NC}"
    echo    "Target kernel: $(uname -r)"
    echo    "Target user:   $(get_target_user)"
    echo    ""

    do_build
    install_binary
    install_shared_assets
    install_context_daemon
    install_config
    install_systemd_units
    install_udev_rules
    deploy_user_config

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Installation complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next step: reboot to activate the Touch Bar."
    echo ""
    show_status
}

# ---------------------------------------------------------------------------
# Setup (user config only — run as the user, not root)
# ---------------------------------------------------------------------------

do_setup() {
    step "User config setup"

    if [ "$EUID" -eq 0 ]; then
        error "Run as your user (not sudo): ./install.sh setup"
    fi

    USER_CONFIG_DIR="${HOME}/.config/reactive-dfr"
    USER_WIDGETS_DIR="${USER_CONFIG_DIR}/widgets"

    info "Deploying to ${USER_CONFIG_DIR}/"

    mkdir -p "${USER_CONFIG_DIR}/contexts" "${USER_WIDGETS_DIR}" "${USER_CONFIG_DIR}/state"

    # Copy config from /etc
    for f in base.toml matcher.toml; do
        if [ ! -f "${USER_CONFIG_DIR}/${f}" ]; then
            cp "${ETC_CONFIG_DIR}/${f}" "${USER_CONFIG_DIR}/${f}"
            info "  Copied: ${f}"
        else
            warn "  Exists: ${f} (not overwritten)"
        fi
    done

    for f in "${ETC_CONFIG_DIR}/contexts/"*.toml; do
        local name="$(basename "$f")"
        if [ ! -f "${USER_CONFIG_DIR}/contexts/${name}" ]; then
            cp "$f" "${USER_CONFIG_DIR}/contexts/${name}"
            info "  Copied: contexts/${name}"
        else
            warn "  Exists: contexts/${name} (not overwritten)"
        fi
    done

    # Copy widgets from system install
    local sys_widgets="${LIB_DIR}/widgets"
    if [ -d "$sys_widgets" ]; then
        for f in "$sys_widgets"/*; do
            [ -f "$f" ] || continue
            local name="$(basename "$f")"
            case "$name" in
                *.template) continue ;;
            esac
            if [ ! -f "${USER_WIDGETS_DIR}/${name}" ]; then
                cp "$f" "${USER_WIDGETS_DIR}/${name}"
                chmod +x "${USER_WIDGETS_DIR}/${name}" 2>/dev/null || true
                info "  Copied: widgets/${name}"
            else
                warn "  Exists: widgets/${name} (not overwritten)"
            fi
        done
    fi

    # Feeder config
    if [ ! -f "${USER_CONFIG_DIR}/feeder_config.toml" ]; then
        if [ -f "${sys_widgets}/feeder_config.toml.template" ]; then
            cp "${sys_widgets}/feeder_config.toml.template" \
               "${USER_CONFIG_DIR}/feeder_config.toml"
            info "  Copied: feeder_config.toml (from template)"
        fi
    fi

    # Enable user services
    info "Enabling user services..."
    systemctl --user daemon-reload
    systemctl --user enable --now touchbar-ctx.service 2>/dev/null || warn "Could not enable touchbar-ctx.service"
    systemctl --user enable --now touchbar-power-monitor.service 2>/dev/null || warn "Could not enable touchbar-power-monitor.service"

    echo ""
    echo -e "${GREEN}User config deployed.${NC}"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    check_root

    step "Removing reactive-dfr"

    # Stop and disable system service
    info "Stopping reactive-dfr.service..."
    systemctl stop reactive-dfr.service 2>/dev/null || true
    systemctl disable reactive-dfr.service 2>/dev/null || true
    rm -f "${SYSTEMD_SYSTEM_DIR}/reactive-dfr.service"
    rm -f "${SYSTEMD_SYSTEM_DIR}/systemd-backlight@backlight:appletb_backlight.service"

    # Remove user services
    info "Removing user services..."
    local target_user="$(get_target_user)"
    local uid uid_run
    uid="$(id -u "$target_user" 2>/dev/null)" && uid_run="/run/user/${uid}"
    if [ -d "${uid_run:-/nonexistent}" ]; then
        runuser -u "$target_user" -- env \
            XDG_RUNTIME_DIR="$uid_run" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${uid_run}/bus" \
            systemctl --user stop touchbar-ctx.service touchbar-power-monitor.service 2>/dev/null || true
        runuser -u "$target_user" -- env \
            XDG_RUNTIME_DIR="$uid_run" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${uid_run}/bus" \
            systemctl --user disable touchbar-ctx.service touchbar-power-monitor.service 2>/dev/null || true
    fi
    rm -f "${SYSTEMD_USER_DIR}/touchbar-ctx.service"
    rm -f "${SYSTEMD_USER_DIR}/touchbar-power-monitor.service"

    systemctl daemon-reload

    # Remove binary
    rm -f "${BIN_DIR}/reactive-dfr"

    # Remove shared assets
    rm -rf "${SHARE_DIR}"

    # Remove context daemon
    rm -rf "${LIB_DIR%%/context-daemon}"

    # Remove system config
    rm -rf "${ETC_CONFIG_DIR%%/config}"

    # Remove udev rules
    rm -f "${UDEV_DIR}/99-touchbar-reactive-dfr.rules"
    rm -f "${UDEV_DIR}/99-touchbar-seat.rules"
    udevadm control --reload-rules 2>/dev/null || true

    echo ""
    echo -e "${GREEN}Uninstallation complete.${NC}"
    echo "User config at ~/.config/reactive-dfr/ was NOT removed (personal data)."
    echo "Remove manually if desired: rm -rf ~/.config/reactive-dfr/"
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

show_status() {
    echo ""
    echo "========================================="
    echo "  reactive-dfr status"
    echo "========================================="
    echo ""

    # Binary
    if [ -x "${BIN_DIR}/reactive-dfr" ]; then
        echo -e "daemon binary:         ${GREEN}INSTALLED${NC}"
    else
        echo -e "daemon binary:         ${YELLOW}NOT INSTALLED${NC}"
    fi

    # System service
    if systemctl is-active reactive-dfr.service >/dev/null 2>&1; then
        echo -e "reactive-dfr.service:  ${GREEN}ACTIVE${NC}"
    elif systemctl is-enabled reactive-dfr.service >/dev/null 2>&1; then
        echo -e "reactive-dfr.service:  ${YELLOW}ENABLED (not running)${NC}"
    else
        echo -e "reactive-dfr.service:  ${YELLOW}NOT ENABLED${NC}"
    fi

    # Context daemon
    if systemctl --user is-active touchbar-ctx.service >/dev/null 2>&1; then
        echo -e "touchbar-ctx.service:  ${GREEN}ACTIVE${NC}"
    elif systemctl --user is-enabled touchbar-ctx.service >/dev/null 2>&1; then
        echo -e "touchbar-ctx.service:  ${YELLOW}ENABLED (not running)${NC}"
    else
        echo -e "touchbar-ctx.service:  ${YELLOW}NOT ENABLED${NC}"
    fi

    # Power monitor
    if systemctl --user is-active touchbar-power-monitor.service >/dev/null 2>&1; then
        echo -e "power-monitor.service: ${GREEN}ACTIVE${NC}"
    elif systemctl --user is-enabled touchbar-power-monitor.service >/dev/null 2>&1; then
        echo -e "power-monitor.service: ${YELLOW}ENABLED (not running)${NC}"
    else
        echo -e "power-monitor.service: ${YELLOW}NOT ENABLED${NC}"
    fi

    # Shared assets
    if [ -d "${SHARE_DIR}" ]; then
        local count
        count=$(ls "${SHARE_DIR}"/*.svg 2>/dev/null | wc -l)
        echo -e "SVG icons:             ${GREEN}${count} installed${NC}"
    else
        echo -e "SVG icons:             ${YELLOW}NOT INSTALLED${NC}"
    fi

    # Context daemon lib
    if [ -f "${LIB_DIR}/daemon.py" ]; then
        echo -e "context daemon:        ${GREEN}INSTALLED${NC}"
    else
        echo -e "context daemon:        ${YELLOW}NOT INSTALLED${NC}"
    fi

    # System config
    if [ -f "${ETC_CONFIG_DIR}/base.toml" ]; then
        local ctx_count
        ctx_count=$(ls "${ETC_CONFIG_DIR}/contexts/"*.toml 2>/dev/null | wc -l)
        echo -e "system config:         ${GREEN}INSTALLED (${ctx_count} contexts)${NC}"
    else
        echo -e "system config:         ${YELLOW}NOT INSTALLED${NC}"
    fi

    # User config
    local user_home
    user_home="$(getent passwd "$(get_target_user)" | cut -d: -f6)"
    if [ -n "$user_home" ] && [ -f "${user_home}/.config/reactive-dfr/base.toml" ]; then
        local widget_count
        widget_count=$(ls "${user_home}/.config/reactive-dfr/widgets/"* 2>/dev/null | wc -l)
        echo -e "user config:           ${GREEN}DEPLOYED (${widget_count} widgets)${NC}"
    else
        echo -e "user config:           ${YELLOW}NOT DEPLOYED (run: ./install.sh setup)${NC}"
    fi

    # Udev rules
    if [ -f "${UDEV_DIR}/99-touchbar-reactive-dfr.rules" ]; then
        echo -e "udev rules:            ${GREEN}INSTALLED${NC}"
    else
        echo -e "udev rules:            ${YELLOW}NOT INSTALLED${NC}"
    fi

    # DRM device
    if readlink /sys/class/drm/card*/device/driver 2>/dev/null | grep -q appletbdrm; then
        echo -e "Touch Bar DRM device:  ${GREEN}present${NC}"
    else
        echo -e "Touch Bar DRM device:  ${YELLOW}NOT PRESENT${NC}"
    fi

    # Backlight
    local bl
    bl="$(cat /sys/class/backlight/appletb_backlight/brightness 2>/dev/null)"
    if [ -n "$bl" ]; then
        echo -e "Touch Bar backlight:   ${GREEN}${bl}${NC}"
    else
        echo -e "Touch Bar backlight:   ${YELLOW}N/A${NC}"
    fi

    echo ""
    echo "Kernel: $(uname -r)"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
    echo "reactive-dfr — reactive Touch Bar daemon"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     Build + install everything + deploy user config (requires sudo)"
    echo "  setup       Deploy user config only (run as your user, not sudo)"
    echo "  uninstall   Remove all system components (keeps user config)"
    echo "  status      Show installation status"
    echo "  help        Show this help"
    echo ""
    echo "Requires appletbdrm-t1 to be installed first."
    echo ""
}

case "${1:-install}" in
    install)
        do_install
        ;;
    setup)
        do_setup
        ;;
    uninstall|remove)
        do_uninstall
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $1\nRun '$0 help' for usage"
        ;;
esac
# Maintainer: emzmo <https://github.com/emzmo>
# Split PKGBUILD: appletbdrm-t1-dkms + reactive-dfr
# One makepkg, two packages: the kernel driver and the userspace daemon.
#
# Usage:
#   makepkg -si          # build and install both packages
#   makepkg -si appletbdrm-t1-dkms  # install only the driver
#   makepkg -si reactive-dfr         # install only the daemon

pkgbase='reactive-dfr-suite'
pkgname=('appletbdrm-t1-dkms' 'reactive-dfr')
pkgver=1.0.0
pkgrel=1
arch=('x86_64')
url="https://github.com/emzmo/reactive-dfr"
license=('GPL-2.0-only' 'MIT')
makedepends=('cargo' 'git' 'linux-headers' 'cairo' 'pango' 'librsvg' 'libdrm' 'libinput' 'pkgconf')
source=(
    "git+https://github.com/emzmo/reactive-dfr.git#branch=main"
    "git+https://github.com/emzmo/appletbdrm-t1.git#tag=v1.0.0-phase0-complete"
)
sha256sums=('SKIP' 'SKIP')

build() {
    cd "${srcdir}/reactive-dfr/daemon"
    cargo build --release
}

# ============================================================================
# Package 1: appletbdrm-t1-dkms
# Kernel DRM driver with T1 iBridge protocol dialect fixes.
# Supports T1 (05ac:8600, 2016-2017) and T2 (05ac:8302, 2018-2020).
# ============================================================================

package_appletbdrm-t1-dkms() {
    pkgdesc="Apple Touch Bar DRM driver (DKMS) with T1 protocol fixes"
    depends=('dkms')
    provides=('appletbdrm-dkms')
    conflicts=('appletbdrm-dkms')

    cd "${srcdir}/appletbdrm-t1"

    # --- DKMS kernel module source ---
    # Copy to /usr/src/appletbdrm-<version>/ for DKMS to build.
    # The module name stays "appletbdrm" so kernel module loading,
    # udev rules, and systemd units that reference it work unchanged.
    local dkms_dir="${pkgdir}/usr/src/appletbdrm-${pkgver}"
    install -Dm644 src/appletbdrm/dkms.conf "${dkms_dir}/dkms.conf"
    install -Dm644 src/appletbdrm/Makefile  "${dkms_dir}/Makefile"
    install -Dm644 src/appletbdrm/appletbdrm.c "${dkms_dir}/appletbdrm.c"
    install -Dm644 src/appletbdrm/LICENSE   "${dkms_dir}/LICENSE"

    # Align dkms.conf version with the PKGBUILD version
    sed -i "s/PACKAGE_VERSION=\"1.2\"/PACKAGE_VERSION=\"${pkgver}\"/" \
        "${dkms_dir}/dkms.conf"

    # --- udev rule: Touch Bar seat isolation ---
    # DRM card: GOTO seat_end (no seat — daemon finds by aspect ratio)
    # Digitizer: ID_SEAT=seat1 (D-Bus safe, no hyphen)
    install -Dm644 etc/udev/rules.d/99-touchbar-seat.rules \
        "${pkgdir}/etc/udev/rules.d/99-touchbar-seat.rules"

    # --- ibridge-config-switch: auto-switch USB config 1→2 at boot ---
    # The T1 boots in config 1 (keyboard-only, dark panel). This service
    # flips it to config 2 (DRM display + multitouch) during sysinit.
    install -Dm755 src/appletbdrm/etc/systemd/system/ibridge-config-switch.sh \
        "${pkgdir}/usr/local/sbin/ibridge-config-switch.sh"
    install -Dm644 src/appletbdrm/etc/systemd/system/ibridge-config-switch.service \
        "${pkgdir}/etc/systemd/system/ibridge-config-switch.service"
}

# ============================================================================
# Package 2: reactive-dfr
# Rust render engine + Python context daemon.
# The Touch Bar adapts to the active window automatically.
# ============================================================================

package_reactive-dfr() {
    pkgdesc="Reactive Touch Bar daemon for Apple T1/T2 Macs on Linux"
    depends=(
        'cairo'
        'pango'
        'librsvg'
        'libdrm'
        'libinput'
        'systemd-libs'
        'python-tomli-w'
        'wl-clipboard'
    )
    optdepends=(
        'appletbdrm-t1-dkms: T1 MacBook Pro support (2016-2017)'
        'playerctl: media widget (MPRIS transport controls)'
        'networkmanager: network info in widget scripts'
    )

    cd "${srcdir}/reactive-dfr"

    # --- Rust daemon binary ---
    install -Dm755 daemon/target/release/reactive-dfr \
        "${pkgdir}/usr/bin/reactive-dfr"

    # --- Shared assets: default config, SVG icons, bundled widget scripts ---
    install -dm755 "${pkgdir}/usr/share/reactive-dfr"
    cp -r daemon/share/reactive-dfr/* "${pkgdir}/usr/share/reactive-dfr/"

    # --- systemd unit (system service: render daemon) ---
    install -Dm644 daemon/etc/systemd/system/reactive-dfr.service \
        "${pkgdir}/etc/systemd/system/reactive-dfr.service"

    # --- systemd backlight drop-in: prevent systemd-backlight from
    # fighting the daemon over appletb_backlight ---
    install -Dm644 "daemon/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service" \
        "${pkgdir}/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service"

    # --- Context daemon (Python) ---
    install -dm755 "${pkgdir}/usr/lib/reactive-dfr/context-daemon/backends"
    install -Dm755 context-daemon/daemon.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/daemon.py"
    install -Dm644 context-daemon/composer.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/composer.py"
    install -Dm644 context-daemon/matcher.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/matcher.py"
    install -Dm644 context-daemon/backends/__init__.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/backends/__init__.py"
    install -Dm644 context-daemon/backends/base.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/backends/base.py"
    install -Dm644 context-daemon/backends/hyprland.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/backends/hyprland.py"
    install -Dm644 context-daemon/backends/sway.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/backends/sway.py"

    # --- Context daemon config: base.toml, matcher.toml, contexts/ ---
    install -dm755 "${pkgdir}/etc/reactive-dfr/config/contexts"
    install -Dm644 context-daemon/config/base.toml \
        "${pkgdir}/etc/reactive-dfr/config/base.toml"
    install -Dm644 context-daemon/config/matcher.toml \
        "${pkgdir}/etc/reactive-dfr/config/matcher.toml"
    cp context-daemon/config/contexts/*.toml \
        "${pkgdir}/etc/reactive-dfr/config/contexts/"

    # --- systemd user unit: context daemon ---
    # Installed to /usr/lib/systemd/user so it's available to all users.
    # Enable with: systemctl --user enable --now touchbar-ctx.service
    install -Dm644 /dev/stdin \
        "${pkgdir}/usr/lib/systemd/user/touchbar-ctx.service" << 'UNIT'
[Unit]
Description=Touch Bar contextual daemon (Hyprland/Sway)
After=reactive-dfr.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/lib/reactive-dfr/context-daemon/daemon.py
WorkingDirectory=/usr/lib/reactive-dfr/context-daemon
Environment=PYTHONPATH=/usr/lib/reactive-dfr/context-daemon
Environment=TOUCHBAR_CONFIG_DIR=/etc/reactive-dfr/config
Restart=on-failure
RestartSec=2

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/reactive-dfr
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
RestrictAddressFamilies=AF_UNIX AF_NETLINK
RestrictNamespaces=true
RestrictRealtime=true

[Install]
WantedBy=default.target
UNIT
}
# Maintainer: emzmo <https://github.com/emzmo>
# PKGBUILD for reactive-dfr
# Reactive Touch Bar daemon: Rust render engine + Python context daemon.
# The Touch Bar adapts to the active window automatically.

pkgname=reactive-dfr
pkgver=0.1.0
pkgrel=1
pkgdesc="Reactive Touch Bar daemon for Apple T1/T2 Macs on Linux"
arch=('x86_64')
url="https://github.com/emzmo/reactive-dfr"
license=('MIT')
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
makedepends=('cargo' 'git')
optdepends=(
    'appletbdrm-t1-dkms: T1 MacBook Pro support (2016-2017)'
    'playerctl: media widget (MPRIS transport controls)'
    'networkmanager: network info in widget scripts'
)
source=("git+${url}.git")
sha256sums=('SKIP')

build() {
    cd "${srcdir}/reactive-dfr/daemon"
    cargo build --release
}

package() {
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
    install -Dm644 daemon/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service \
        "${pkgdir}/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service"

    # --- Context daemon (Python) ---
    # Install to /usr/lib/reactive-dfr/context-daemon/
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
    # Users enable it with: systemctl --user enable touchbar-ctx.service
    install -dm755 "${pkgdir}/usr/lib/systemd/user"
    cat > "${pkgdir}/usr/lib/systemd/user/touchbar-ctx.service" << 'EOF'
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
EOF
}
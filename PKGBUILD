# Maintainer: emzmo <https://github.com/emzmo>
# PKGBUILD for reactive-dfr
# Reactive Touch Bar daemon (Rust render engine + Python context daemon).
# Requires appletbdrm-t1-dkms for the kernel driver.

pkgname=reactive-dfr
pkgver=1.0.0
pkgrel=1
pkgdesc="Reactive Touch Bar daemon for Apple T1/T2 Macs — contextual switching, screensaver, widgets"
arch=('x86_64')
url="https://github.com/emzmo/reactive-dfr"
license=('GPL-2.0-only' 'MIT')
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
    'appletbdrm-t1-dkms: T1 MacBook Pro kernel driver (2016-2017)'
    'python-feedparser: RSS news in screensaver feeder widget'
    'khal: calendar events in screensaver feeder widget'
    'playerctl: MPRIS media transport controls'
)
makedepends=('cargo' 'git' 'pkgconf')
provides=('not-quite-tiny-dfr' 'tiny-dfr')
conflicts=('not-quite-tiny-dfr' 'tiny-dfr')
install=reactive-dfr.install
source=("git+${url}.git#tag=v${pkgver}")
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

    # --- Shared assets: SVG icons, default config, shipped widget scripts ---
    install -dm755 "${pkgdir}/usr/share/reactive-dfr"
    cp -r daemon/share/reactive-dfr/* "${pkgdir}/usr/share/reactive-dfr/"

    # --- Context daemon (Python) ---
    install -dm755 "${pkgdir}/usr/lib/reactive-dfr/context-daemon/backends"
    install -dm755 "${pkgdir}/usr/lib/reactive-dfr/context-daemon/scripts"
    install -dm755 "${pkgdir}/usr/lib/reactive-dfr/context-daemon/widgets"

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

    install -Dm644 context-daemon/scripts/power_monitor.py \
        "${pkgdir}/usr/lib/reactive-dfr/context-daemon/scripts/power_monitor.py"

    # Widgets (copied to ~/.config/reactive-dfr/widgets/ by the setup command)
    for f in context-daemon/widgets/*; do
        [ -f "$f" ] && install -Dm644 "$f" \
            "${pkgdir}/usr/lib/reactive-dfr/context-daemon/widgets/$(basename "$f")"
    done

    # --- System config: base.toml, matcher.toml, contexts/ ---
    install -dm755 "${pkgdir}/etc/reactive-dfr/config/contexts"
    install -Dm644 context-daemon/config/base.toml \
        "${pkgdir}/etc/reactive-dfr/config/base.toml"
    install -Dm644 context-daemon/config/matcher.toml \
        "${pkgdir}/etc/reactive-dfr/config/matcher.toml"
    cp context-daemon/config/contexts/*.toml \
        "${pkgdir}/etc/reactive-dfr/config/contexts/"

    # --- Systemd: system service (render daemon) ---
    install -Dm644 daemon/etc/systemd/system/reactive-dfr.service \
        "${pkgdir}/etc/systemd/system/reactive-dfr.service"

    # --- Systemd: backlight drop-in (prevent systemd-backlight conflict) ---
    install -Dm644 daemon/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service \
        "${pkgdir}/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service"

    # --- Systemd: user services (context daemon + power monitor) ---
    install -Dm644 context-daemon/systemd/touchbar-ctx.service \
        "${pkgdir}/usr/lib/systemd/user/touchbar-ctx.service"
    install -Dm644 context-daemon/systemd/touchbar-power-monitor.service \
        "${pkgdir}/usr/lib/systemd/user/touchbar-power-monitor.service"

    # --- Udev rules ---
    install -Dm644 daemon/etc/udev/rules.d/99-touchbar-reactive-dfr.rules \
        "${pkgdir}/etc/udev/rules.d/99-touchbar-reactive-dfr.rules"
    install -Dm644 daemon/etc/udev/rules.d/99-touchbar-seat.rules \
        "${pkgdir}/etc/udev/rules.d/99-touchbar-seat.rules"
}
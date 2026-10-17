#!/usr/bin/env bash
# install.sh — instala el daemon contextual de la Touch Bar.
#   Copia:  scripts -> /usr/local/lib/reactive-dfr
#           config  -> /etc/reactive-dfr/config
#           unit    -> ~/.config/systemd/user/reactive-dfr.service
#   Permisos: cede /etc/tiny-dfr/config.toml al usuario (rename atómico)
# Luego arranca la unit de usuario (sin sudo) y habilita el autostart.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBDIR="/usr/local/lib/reactive-dfr"
CONFDIR="/etc/reactive-dfr"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
UNIT="$TARGET_HOME/.config/systemd/user/reactive-dfr.service"

# --- 1. scripts + CLI tool + backends ---
install -d "$LIBDIR/backends"
install -m 0755 "$SRC/daemon.py" "$SRC/matcher.py" "$SRC/composer.py" "$LIBDIR/"
install -m 0755 "$SRC/backends/"*.py "$LIBDIR/backends/"
install -Dm 0755 "$SRC/touchbar-ctx.py" "/usr/local/bin/touchbar-ctx"

# --- 2. config (base + matcher + contextos) ---
install -d "$CONFDIR/config/contexts"
install -m 0644 "$SRC/config/base.toml" "$SRC/config/matcher.toml" "$CONFDIR/config/"
install -m 0644 "$SRC/config/contexts/"*.toml "$CONFDIR/config/contexts/"

# --- 3. permisos: tiny-dfr lee /etc/tiny-dfr/config.toml (ruta hardcodeada)
#        El daemon lo reescribe con rename atómico (temp+rename en el MISMO
#        directorio) -> el usuario debe poder escribir en el directorio.
#        Los SVGs son de solo lectura, ceder el dir no cambia su contenido.
if [ "$(id -u)" -eq 0 ]; then
    chown "$TARGET_USER:$TARGET_USER" /etc/tiny-dfr
    chmod 755 /etc/tiny-dfr
    echo "cedido /etc/tiny-dfr a $TARGET_USER (rename atómico del daemon)"
else
    echo "AVISO: /etc/tiny-dfr no es escribible por $TARGET_USER."
    echo "  Ejecuta: sudo chown $TARGET_USER:$TARGET_USER /etc/tiny-dfr"
fi

# --- 4. unit systemd de usuario ---
install -d "$TARGET_HOME/.config/systemd/user"
sed -e "s|@LIBDIR@|$LIBDIR|g" "$SRC/reactive-dfr.service.in" > "$UNIT"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/systemd/user"

echo "daemon instalado:"
echo "  scripts -> $LIBDIR"
echo "  config  -> $CONFDIR"
echo "  unit    -> $UNIT"

# --- 5. arranque (como el usuario target, con su bus de sesión) ---
# Si nos ejecutamos como root (sudo), usamos runuser para hablar con el bus
# del usuario real; XDG_RUNTIME_DIR apunta a su dir de sesión.
RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")"
if [ "$(id -u)" -eq 0 ]; then
    run_sysctl() {
        runuser -u "$TARGET_USER" -- env \
            XDG_RUNTIME_DIR="$RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
            systemctl --user "$@"
    }
else
    run_sysctl() { systemctl --user "$@"; }
fi

run_sysctl daemon-reload || echo "AVISO: daemon-reload fallo (bus de sesion inaccesible)"
run_sysctl enable --now reactive-dfr.service || echo "AVISO: no se pudo habilitar el servicio"
run_sysctl status --no-pager reactive-dfr.service || true

echo "hecho."

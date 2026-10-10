# touchbar-daemon — Touch Bar contextual layout daemon

Detects the active window and swaps the tiny-dfr Touch Bar layout on the fly,
macOS-style: each app gets its own buttons.

## Supported compositors

| Compositor | Method | Event-driven? |
|---|---|---|
| **Hyprland** | `.socket2.sock` events + `hyprctl -j activewindow` | Yes (socket) |
| **Sway/i3** | `swaymsg -t get_tree` / `i3-msg -t get_tree` polling | Poll (1s) |

Auto-detection: checks `HYPRLAND_INSTANCE_SIGNATURE`, `SWAYSOCK`, `I3SOCK`.
Force a backend with `--backend sway`.

## Architecture

```
Compositor events ─► daemon.py ──► matcher.py ──► composer.py ──► /etc/tiny-dfr/config.toml
   (Hyprland socket2     (loop)        (rules)        (merge+rename)      (tiny-dfr hot-reload)
    or Sway polling)
```

```
backends/
├── __init__.py     # detect_backend() auto-detection
├── base.py         # CompositorBackend ABC
├── hyprland.py     # HyprlandBackend: socket events + hyprctl
└── sway.py         # SwayBackend: swaymsg -t get_tree polling
```

## Layout de ficheros

```
/etc/touchbar-daemon/config/
├── base.toml            # globales + MediaLayerKeys (capa Fn, fija)
├── matcher.toml         # class/title → contexto
└── contexts/
    ├── default.toml     # F1–F12
    ├── browser.toml     # pestañas, navegación, recarga
    ├── terminal.toml    # señales, bufer, historial
    ├── media.toml       # reproducción, volumen
    ├── files.toml       # gestor de archivos
    ├── comms.toml       # mensajería
    ├── ide.toml         # IDE/code editor
    ├── aseprite.toml    # pixel art editor
    ├── gimp.toml        # image editor
    ├── gaming.toml      # gaming system controls
    ├── virtual-desktops.toml
    ├── screenshot.toml
    ├── clipboard.toml
    └── system.toml
```

## Uso

```sh
sudo install.sh          # instala scripts, config, CLI y unit; arranca el daemon
systemctl --user status touchbar-daemon
journalctl --user -u touchbar-daemon -f   # logs
python3 daemon.py --once                  # aplica el contexto actual y sale
python3 daemon.py --backend sway          # fuerza Sway backend
```

## CLI: touchbar-ctx

```sh
touchbar-ctx list              # lista todos los contextos
touchbar-ctx show browser      # muestra el layout de un contexto
touchbar-ctx new myapp --class "myapp"  # scaffolds un contexto nuevo
touchbar-ctx test browser      # aplica un contexto ahora
touchbar-ctx validate          # valida todos los TOML
touchbar-ctx matcher           # muestra las reglas del matcher
touchbar-ctx backends          # lista los backends disponibles
```

## Añadir un contexto

### Usando el CLI (recomendado):
```sh
sudo touchbar-ctx new myapp --class "MyApp" --class "myapp" --description "My app context"
sudo touchbar-ctx test myapp
```

### Manual:
1. Crear `config/contexts/<nombre>.toml` con `PrimaryLayerKeys` (ButtonConfig
   de tiny-dfr: `Text`/`Icon`/`Action` string o array, PascalCase).
2. Añadir una regla en `config/matcher.toml`.
3. El daemon lee la config en cada evento (no hace falta reiniciarlo).

## Notas

- `class` gana sobre `title` entre reglas (la primera coincidencia de la
  lista manda).
- Hyprland: `hyprctl dispatch` ha cambiado a sintaxis Lua en Hyprland 0.55+ —
  el daemon no lo usa (solo `hyprctl -j activewindow`).
- Sway: usa polling (1s) porque Sway no tiene un socket de eventos tan
  conveniente como Hyprland. El impacto en CPU es mínimo.

## Further reading

The `docs/` directory at the project root has the full architecture and
research material. For this component specifically see:

- `docs/04-userspace-context.md` §4.1 (macOS responder chain — the model
  this daemon approximates), §4.5 (context switch on focus change)
- `docs/08-current-codebase-map.md` §8.4 (this daemon's `file:line` map)
- `docs/09-gaps-and-research-questions.md` §9.4.4 (per-responder
  granularity gap), §9.6.6 (`composer.py` cannot serialize extended fields)
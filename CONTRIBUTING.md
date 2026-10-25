# Contributing to reactive-dfr

First of all, **thank you** for considering contributing to this project! 
This project exists because people like you care about giving new life to 
hardware that others consider obsolete.

## Code of Conduct

Be respectful. Be patient. Be helpful. We were all beginners once. 
Personal attacks, harassment, or toxicity will not be tolerated.

## How Can I Contribute?

### Reporting Bugs

Before creating a bug report, please:
1. Check if the issue is already reported in [Issues](../../issues)
2. Update to the latest version and see if the bug persists
3. Collect diagnostic info:
   - Distro and kernel version (`uname -r`)
   - MacBook model (`sysctl hw.model`)
   - Logs: `sudo dmesg | grep appletbdrm`
   - Daemon logs: `journalctl -u reactive-dfr`

Use the **Bug Report** template when creating a new issue.

### Suggesting Enhancements

Enhancement suggestions are welcome! Please:
1. Check if the suggestion was already made
2. Provide a clear description of what you want
3. Explain why it would be useful (use case)
4. If possible, describe how you imagine it working

### Pull Requests

PRs are welcome! Here's how:

1. Fork the repo
2. Create a branch: `git checkout -b feature/my-feature`
3. Commit your changes using [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add new widget for weather
   fix: resolve crash on config reload
   docs: update installation guide
   ```
4. Push: `git push origin feature/my-feature`
5. Open a PR and describe what you changed and why

#### PR Guidelines

- **One feature per PR** — don't bundle unrelated changes
- **Keep PRs small** — easier to review, faster to merge
- **Test on your machine** — make sure it compiles and runs
- **Update docs** — if you add a config option, document it
- **Don't break existing configs** — backward compatibility matters

## Development Setup

### Prerequisites

- Rust (stable toolchain)
- Python 3.11+
- `cairo`, `pango`, `librsvg`, `libdrm`, `libinput` development headers
- A MacBook with T1 or T2 chip (or help us test on other hardware)

### Building

```bash
# Clone
git clone https://github.com/emzmo/reactive-dfr.git
cd reactive-dfr

# Build the daemon
cd daemon
cargo build --release

# Install
sudo install -m 755 target/release/reactive-dfr /usr/bin/reactive-dfr
```

## Architecture

```
reactive-dfr/
├── daemon/              — Rust render engine (DRM + cairo + libinput)
├── context-daemon/      — Python contextual switching (Hyprland/Sway IPC)
└── docs/                — Documentation
```

Read `docs/architecture.md` for a detailed overview of how the
components interact.

## Style Guide

### Git Commits

We use Conventional Commits:

| Type       | When to use                                      |
|------------|--------------------------------------------------|
| `feat`     | New feature                                      |
| `fix`      | Bug fix                                          |
| `docs`     | Documentation only                               |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test`     | Adding tests                                     |
| `chore`    | Build, deps, config, etc.                        |

### Code Style

- **Rust** (`daemon/`): Follow `rustfmt` defaults. Run `cargo fmt` before
  committing.
- **Python** (`context-daemon/`): Follow PEP 8. Run `flake8` or `ruff`
  before committing.
- **Shell scripts**: Use `shellcheck` if available.

### Comments

Comments should explain **WHY**, not **WHAT**:

```rust
// GOOD: T1 sends a 16-byte short transfer before bulk replies
// BAD: // drains the preamble
```

## Testing

Currently this project doesn't have automated tests (we're working on it).
For now:

1. Test on your hardware before submitting a PR
2. Verify the daemon starts: `systemctl start reactive-dfr`
3. Verify the Touch Bar renders
4. Verify context switching works (switch apps)
5. Verify the screensaver activates on idle

## Questions?

Feel free to open a [Discussion](../../discussions) for questions,
or reach out via [Issues](../../issues).

Again, thank you for helping make hardware last longer! 🖤
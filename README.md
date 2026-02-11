# Surfer macOS Build

Build and package [Surfer](https://surfer-project.org/) waveform viewer as a native macOS `.app`.

## Quick Start

```bash
git clone --recursive https://github.com/ktywb/surfer_mac_test.git
cd surfer_mac_test
./build_surfer.sh
```

The script will:
1. Check for Rust and Xcode Command Line Tools
2. Pull latest upstream code and apply patches
3. Compile in release mode with parallel jobs
4. Package as `Surfer.app` with icon, file associations, and code signing

## Patches

| Patch | Description |
|-------|-------------|
| `file_dialog_macos_fix.patch` | Fix macOS file dialog for `.surf.ron` compound extensions |
| `theme_persistence.patch` | Persist theme preference across app restarts |

Patches are applied automatically by `build_surfer.sh`. See [patchs/README.md](patchs/README.md) for details.

## File Associations

After building, Surfer can open these file types via double-click or "Open With":

- `.vcd` `.fst` `.ghw` `.ftr` — Waveform files
- `.ron` — Surfer state files
- `.sucl` — Surfer command files

## Project Structure

```
├── build_surfer.sh      # Build and packaging script
├── patchs/              # macOS-specific patches
└── surfer/              # Upstream repo (git submodule)
```

## Requirements

- macOS 11+
- Xcode Command Line Tools
- Rust toolchain (installed automatically if missing)

# Surfer macOS Patches

## file_dialog_macos_fix.patch

Fixes an issue where macOS file dialogs cannot properly recognize compound extensions (such as `.surf.ron`).

### Changes

1. **Fix loading state files** - macOS file dialog now correctly recognizes `.surf.ron` files
2. **Fix save dialog default filename** - Save dialog automatically populates default filename with extension (e.g., `untitled.surf.ron`)
3. **Cross-platform compatibility** - Handles both macOS and non-macOS systems

### Applying the Patch

#### Method 1: Using git apply (Recommended)

```bash
cd /Users/lyu/git_prj/surfer/surfer
git apply ../patchs/file_dialog_macos_fix.patch
```

#### Method 2: Using patch command

```bash
cd /Users/lyu/git_prj/surfer/surfer
patch -p1 < ../patchs/file_dialog_macos_fix.patch
```

### Workflow

```bash
# 1. Pull latest code
cd /Users/lyu/git_prj/surfer/surfer
git pull

# 2. Apply patch
git apply ../patchs/file_dialog_macos_fix.patch

# 3. Build
cargo build --release

# Or use the build script from parent directory
cd /Users/lyu/git_prj/surfer
./build_surfer.sh
```

### Check Patch Status

```bash
# Check if patch can be applied cleanly
git apply --check ../patchs/file_dialog_macos_fix.patch

# If there are conflicts, view details
git apply --reject ../patchs/file_dialog_macos_fix.patch
```

### Reverting the Patch

```bash
# If you need to revert the patch
git apply -R ../patchs/file_dialog_macos_fix.patch

# Or directly restore the file
git checkout libsurfer/src/file_dialog.rs
```

### Modified Files

- `libsurfer/src/file_dialog.rs`

### Created

2026-02-11

---

## theme_persistence.patch

Makes theme settings persistent when saving state files, automatically restoring the previous theme when reloading state files.

### Changes

1. **Theme state persistence** - Adds `theme_name` field to `UserState` to save current theme name
2. **Automatic theme restoration** - When loading state files, automatically restores the saved theme
3. **Read default theme** - If no theme is saved in state file, reads from `config.toml`
4. **Cross-platform support** - Supports both macOS and WASM platforms
5. **Instant save on theme change** - Theme preference is saved immediately when changed, without requiring manual state file save
6. **Startup visuals fix** - Applies theme visuals correctly on startup to prevent mixed dark/light UI

### Applying the Patch

#### Method 1: Using git apply (Recommended)

```bash
cd /Users/lyu/git_prj/surfer/surfer
git apply ../patchs/theme_persistence.patch
```

#### Method 2: Using patch command

```bash
cd /Users/lyu/git_prj/surfer/surfer
patch -p1 < ../patchs/theme_persistence.patch
```

### Workflow

```bash
# 1. Pull latest code
cd /Users/lyu/git_prj/surfer/surfer
git pull

# 2. Apply patch
git apply ../patchs/theme_persistence.patch

# 3. Build
cargo build --release

# Or use build_surfer.sh (automatically applies all patches)
cd /Users/lyu/git_prj/surfer
./build_surfer.sh
```

### Testing Theme Persistence

```bash
# 1. Open Surfer
# 2. Change theme in menu (e.g., switch to light+)
# 3. Theme is saved automatically - no need to save state file
# 4. Close Surfer
# 5. Open Surfer again (or open any waveform file)
# 6. Verify theme is restored to light+
```

### How It Works

The theme preference is saved to `~/Library/Application Support/org.surfer-project.surfer/last_theme` immediately when you change themes. This file is read on startup, so your theme choice persists across sessions without needing to save state files.

### Reverting the Patch

```bash
# If you need to revert the patch
git apply -R ../patchs/theme_persistence.patch

# Or directly restore files
git checkout libsurfer/src/state.rs libsurfer/src/lib.rs
```

### Modified Files

- `libsurfer/src/state.rs`
- `libsurfer/src/lib.rs`

### Created

2026-02-11

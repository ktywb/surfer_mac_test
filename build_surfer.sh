#!/bin/bash
set -e 

APP_NAME="Surfer"
APP_DIR="${APP_NAME}.app"

echo "=== 1. Check Environment ==="

# 1. Check Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found, requesting installation..."
    xcode-select --install
    exit 1
fi

# 2. Check Rust
if ! command -v cargo &> /dev/null; then
    echo "Rust not found, installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust installed: $(cargo --version)"
fi

# echo "=== 2. Download Source Code ==="

# if [ -d "surfer" ]; then
#     echo "Cleaning old directory..."
#     rm -rf surfer
# fi

# # Clone with all submodules
# git clone --recursive https://gitlab.com/surfer-project/surfer.git
rm -rf "$APP_DIR"
cd surfer

# Update source code
echo "=== 2. Update Source Code ==="
echo "Restoring modified files and pulling latest code..."
git checkout libsurfer/src/file_dialog.rs 2>/dev/null || true
git checkout libsurfer/src/state.rs 2>/dev/null || true
git checkout libsurfer/src/lib.rs 2>/dev/null || true
git pull

# Apply macOS file dialog patch
echo "Applying macOS file dialog patch..."
PATCH_FILE="../patchs/file_dialog_macos_fix.patch"
if [ -f "$PATCH_FILE" ]; then
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        echo "File dialog patch applied successfully"
    else
        echo "Patch may already be applied or has conflicts, skipping..."
    fi
else
    echo "Patch file not found, skipping"
fi

# Apply theme persistence patch
echo "Applying theme persistence patch..."
THEME_PATCH="../patchs/theme_persistence.patch"
if [ -f "$THEME_PATCH" ]; then
    if git apply --check "$THEME_PATCH" 2>/dev/null; then
        git apply "$THEME_PATCH"
        echo "Theme persistence patch applied successfully"
    else
        echo "Patch may already be applied or has conflicts, skipping..."
    fi
else
    echo "Theme persistence patch file not found, skipping"
fi

# cargo clean
# # Update submodules
# echo "Updating Git submodules..."
# git submodule update --init --recursive

echo "=== 3. Build (Release Mode) ==="
# Enable parallel compilation
NCPU=$(sysctl -n hw.ncpu)
echo "Detected $NCPU CPU cores, enabling parallel compilation..."
cargo build --release -j $NCPU

BINARY_PATH="target/release/surfer"
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary file not found after compilation."
    exit 1
fi

echo "=== 4. Package as macOS App (Wrapper Approach) ==="
cd ..
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# --- Key modifications start ---

# 1. Copy the actual binary with a different name (e.g. surfer-bin)
REAL_BIN_NAME="surfer-bin"
cp "surfer/$BINARY_PATH" "$APP_DIR/Contents/MacOS/$REAL_BIN_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$REAL_BIN_NAME"

# 2. Create Swift wrapper to handle macOS file open events
WRAPPER_SOURCE="$APP_DIR/Contents/MacOS/wrapper.swift"
WRAPPER_PATH="$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$WRAPPER_SOURCE" <<'SWIFT'
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var hasLaunched = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.count > 1 {
            // Launch from command line with arguments
            launchSurfer(with: Array(args[1...]))
        } else {
            // No arguments, wait 0.1s for open event
            // If none, launch Surfer with empty window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.hasLaunched {
                    self.launchSurfer(with: [])
                }
            }
        }
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        hasLaunched = true
        launchSurfer(with: [filename])
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasLaunched = true
        if let first = filenames.first {
            launchSurfer(with: [first])
        }
    }
    
    func launchSurfer(with arguments: [String]) {
        let binPath = Bundle.main.bundlePath + "/Contents/MacOS/surfer-bin"
        
        // Use execv to replace this process with surfer-bin.
        // This keeps the same PID and Dock icon — exactly one icon.
        let allArgs = [binPath] + arguments
        let cArgs = allArgs.map { strdup($0) } + [nil]
        execv(binPath, cArgs)
        
        // execv only returns on failure — fallback to Process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binPath)
        task.arguments = arguments
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
SWIFT

echo "Compiling Swift wrapper..."
/usr/bin/swiftc "$WRAPPER_SOURCE" -o "$WRAPPER_PATH" -framework Cocoa
rm "$WRAPPER_SOURCE"

# Grant execution permission
chmod +x "$WRAPPER_PATH"

# --- Key modifications end ---

# Generate Info.plist
# Note: CFBundleExecutable must be "Surfer" (the wrapper executable name)
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.gitlab.surfer-project.surfer</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array><string>vcd</string><string>fst</string><string>ghw</string><string>ftr</string></array>
            <key>CFBundleTypeName</key>
            <string>Waveform File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
        </dict>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array><string>ron</string></array>
            <key>CFBundleTypeName</key>
            <string>Surfer State File</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
        </dict>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array><string>sucl</string></array>
            <key>CFBundleTypeName</key>
            <string>Surfer Command File</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# Create macOS standard app icon
echo "Generating macOS app icon..."
SOURCE_ICON="surfer/surfer/assets/com.gitlab.surferproject.surfer.png"

if [ -f "$SOURCE_ICON" ]; then
    # Create temporary iconset directory
    ICONSET_DIR="$APP_DIR/Contents/Resources/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # Generate icons at various sizes using sips (macOS standard)
    sips -z 16 16     "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -z 32 32     "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -z 64 64     "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -z 256 256   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -z 512 512   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
    
    # Convert to .icns format
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    
    # Clean up temporary files
    rm -rf "$ICONSET_DIR"
    
    echo "Icon generated successfully"
else
    echo "Source icon not found, creating placeholder"
    touch "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Code signing
echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "=== 5. Refresh macOS Launch Services Cache ==="
echo "   (This step is necessary to register file associations)"

# This is critical for registering new file associations
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"

echo ""
echo "=== Build Successful! ==="
echo "Surfer.app is in the current directory."
echo ""
echo "Usage Instructions:"
echo "1. Move Surfer.app to /Applications folder (recommended)."
echo "2. Right-click any .vcd/.fst/.ghw/.ftr file -> Open With -> Choose Surfer."
echo "3. You can also double-click .surf.ron (state files) or .sucl (command files)."
echo "4. If file opening issues occur, check debug log: cat /tmp/surfer_launch.log"
echo "5. If still not working, restart Finder (Option+Right-click Finder icon in Dock -> Relaunch)."

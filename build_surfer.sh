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
git checkout -- libsurfer/src/file_dialog.rs \
    libsurfer/src/state.rs \
    libsurfer/src/lib.rs \
    libsurfer/src/hierarchy.rs \
    libsurfer/src/message.rs \
    libsurfer/src/system_state.rs \
    libsurfer/src/wave_data.rs \
    default_config.toml \
    surfer/assets/com.gitlab.surferproject.surfer.png 2>/dev/null || true
git pull

# Apply macOS file dialog patch
echo "Applying macOS file dialog patch..."
PATCH_FILE="../patchs/file_dialog_macos_fix.patch"
if [ -f "$PATCH_FILE" ]; then
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        printf '\033[32mFile dialog patch applied successfully\033[0m\n'
    else
        printf '\033[33mPatch may already be applied or has conflicts, skipping...\033[0m\n'
    fi
else
    printf '\033[31mPatch file not found, skipping\033[0m\n'
fi

# Apply macOS enhancements patch (theme persistence, settings persistence, CJK font support, scope expansion state)
echo "Applying macOS enhancements patch..."
ENHANCE_PATCH="../patchs/surfer_macos_enhancements.patch"
if [ -f "$ENHANCE_PATCH" ]; then
    if git apply --check "$ENHANCE_PATCH" 2>/dev/null; then
        git apply "$ENHANCE_PATCH"
        printf '\033[32mmacOS enhancements patch applied successfully\033[0m\n'
    else
        printf '\033[33mPatch may already be applied or has conflicts, skipping...\033[0m\n'
    fi
else
    printf '\033[31mmacOS enhancements patch file not found, skipping\033[0m\n'
fi

# cargo clean
# # Update submodules
# echo "Updating Git submodules..."
# git submodule update --init --recursive

echo "=== 3. Generate macOS Squircle Icon ==="
SOURCE_ICON="surfer/assets/com.gitlab.surferproject.surfer.png"
SQUIRCLE_ICON="/tmp/surfer_squircle_1024.png"

if [ -f "$SOURCE_ICON" ]; then
    ICON_GEN="/tmp/surfer_icon_gen.swift"
    cat > "$ICON_GEN" <<'ICONSWIFT'
import Cocoa

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: icon_gen <source.png> <output.png>\n", stderr)
    exit(1)
}

let srcPath = args[1]
let dstPath = args[2]
let size: CGFloat = 1024

guard let srcImage = NSImage(contentsOfFile: srcPath) else {
    fputs("Error: Cannot load source image\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

// macOS standard: ~10% transparent margin on each side
// Squircle occupies ~80% of canvas, centered
let margin = size * 0.10
let squircleSize = size - margin * 2
let squircleRect = NSRect(x: margin, y: margin, width: squircleSize, height: squircleSize)

// macOS Big Sur squircle: continuous corner radius ~ 22.37% of squircle size
let cornerRadius = squircleSize * 0.2237
let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Clip to squircle, fill background, draw icon
squirclePath.addClip()

// Solid dark gray background (#2d2d2d)
let bgColor = NSColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)
bgColor.setFill()
squirclePath.fill()

// Draw original icon centered within squircle with 10% inner padding
let iconPadding = squircleSize * 0.10
let iconRect = NSRect(x: margin + iconPadding, y: margin + iconPadding,
    width: squircleSize - iconPadding * 2, height: squircleSize - iconPadding * 2)
srcImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

// Subtle inner border for depth
NSColor(white: 1.0, alpha: 0.08).setStroke()
squirclePath.lineWidth = 2.0
squirclePath.stroke()

NSGraphicsContext.restoreGraphicsState()

let pngData = rep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: dstPath))
ICONSWIFT

    echo "Compiling icon generator..."
    /usr/bin/swiftc "$ICON_GEN" -o /tmp/surfer_icon_gen -framework Cocoa
    /tmp/surfer_icon_gen "$SOURCE_ICON" "$SQUIRCLE_ICON"
    rm -f "$ICON_GEN" /tmp/surfer_icon_gen

    # Replace source icon so surfer-bin embeds the squircle version at compile time
    cp "$SQUIRCLE_ICON" "$SOURCE_ICON"
    echo "Squircle icon generated and applied to source assets"
else
    echo "Source icon not found, skipping icon generation"
fi

echo "=== 4. Build (Release Mode) ==="
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
        let dylibPath = Bundle.main.bundlePath + "/Contents/Frameworks/dock_menu.dylib"
        
        // Inject Dock menu helper into surfer-bin
        setenv("DYLD_INSERT_LIBRARIES", dylibPath, 1)
        
        // Use execv to replace this process with surfer-bin.
        // This keeps the same PID and Dock icon (exactly one icon).
        let allArgs = [binPath] + arguments
        let cArgs = allArgs.map { strdup($0) } + [nil]
        execv(binPath, cArgs)
        
        // execv only returns on failure, fallback to Process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binPath)
        task.arguments = arguments
        task.environment = ["DYLD_INSERT_LIBRARIES": dylibPath]
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

# 3. Create dynamic library for Dock right-click "New Window" menu
echo "Creating Dock menu helper..."
mkdir -p "$APP_DIR/Contents/Frameworks"
DOCK_MENU_SOURCE="$APP_DIR/Contents/Frameworks/dock_menu.m"
DOCK_MENU_LIB="$APP_DIR/Contents/Frameworks/dock_menu.dylib"

cat > "$DOCK_MENU_SOURCE" <<'OBJC'
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// Provides "New Window" item in Dock right-click menu

static NSMenu* dockMenu(id self, SEL _cmd, NSApplication* sender) {
    NSMenu* menu = [[NSMenu alloc] init];
    NSMenuItem* item = [[NSMenuItem alloc]
        initWithTitle:@"New Window"
        action:@selector(dockNewWindow)
        keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return menu;
}

static void dockNewWindow(id self, SEL _cmd) {
    NSString* appPath = [[NSBundle mainBundle] bundlePath];
    NSURL* appURL = [NSURL fileURLWithPath:appPath];
    if (@available(macOS 10.15, *)) {
        NSWorkspaceOpenConfiguration* config = [NSWorkspaceOpenConfiguration configuration];
        config.createsNewApplicationInstance = YES;
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL
                                             configuration:config
                                         completionHandler:nil];
    }
}

__attribute__((constructor))
static void installDockMenu(void) {
    // Prevent injection into child processes
    unsetenv("DYLD_INSERT_LIBRARIES");

    // Wait for winit/eframe to set up the app delegate, then add Dock menu
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            id delegate = [NSApp delegate];
            if (delegate) {
                Class cls = object_getClass(delegate);
                class_addMethod(cls, @selector(applicationDockMenu:),
                    (IMP)dockMenu, "@@:@");
                class_addMethod(cls, @selector(dockNewWindow),
                    (IMP)dockNewWindow, "v@:");
            }
        });
    });
}
OBJC

clang -dynamiclib -framework AppKit \
    -mmacosx-version-min=11.0 \
    "$DOCK_MENU_SOURCE" -o "$DOCK_MENU_LIB"
rm "$DOCK_MENU_SOURCE"
echo "Dock menu helper created"

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

# Create .icns from the squircle icon
echo "Generating macOS app icon (.icns)..."
SQUIRCLE_ICON="/tmp/surfer_squircle_1024.png"

if [ -f "$SQUIRCLE_ICON" ]; then
    ICONSET_DIR="$APP_DIR/Contents/Resources/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    sips -z 16 16     "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -z 32 32     "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -z 64 64     "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -z 256 256   "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -z 512 512   "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$SQUIRCLE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
    
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR" "$SQUIRCLE_ICON"
    
    echo "App icon (.icns) generated successfully"
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

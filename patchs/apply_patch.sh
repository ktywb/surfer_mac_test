#!/bin/bash
# Quick script to apply Surfer macOS patches

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/file_dialog_macos_fix.patch"
SURFER_DIR="$SCRIPT_DIR/../surfer"

echo "=== Surfer macOS Patch Application Tool ==="
echo ""

# Check if in correct directory
if [ ! -d "$SURFER_DIR" ]; then
    echo "Error: surfer directory not found"
    echo "   Current script location: $SCRIPT_DIR"
    echo "   Expected surfer directory: $SURFER_DIR"
    exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: patch file not found"
    echo "   Expected patch file: $PATCH_FILE"
    exit 1
fi

cd "$SURFER_DIR"

echo "Checking patch status..."
if git apply --check "$PATCH_FILE" 2>/dev/null; then
    echo "Patch can be applied cleanly"
    echo ""
    echo "Applying patch..."
    git apply "$PATCH_FILE"
    echo "Patch applied successfully!"
    echo ""
    echo "Modified files:"
    git diff --stat
    echo ""
    echo "Now you can run the build script:"
    echo "   cd $SCRIPT_DIR/.."
    echo "   ./build_surfer.sh"
else
    echo "Patch cannot be applied directly, conflicts may exist"
    echo ""
    echo "Possible reasons:"
    echo "1. Patch has already been applied"
    echo "2. Source code has been updated, causing context mismatch"
    echo "3. Files have been manually modified"
    echo ""
    echo "Suggested actions:"
    echo "1. Check file status: git status libsurfer/src/file_dialog.rs"
    echo "2. View current changes: git diff libsurfer/src/file_dialog.rs"
    echo "3. If needed, restore file first: git checkout libsurfer/src/file_dialog.rs"
    echo "4. Then re-run this script"
    exit 1
fi

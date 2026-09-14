#!/bin/bash
# Export debug APK with Godot headless and install it to the connected device.
set -euo pipefail
cd "$(dirname "$0")"

PRESET_NAME="Android"
APK_PATH="build/eggs-debug.apk"
PACKAGE_NAME="com.zihenggao.eggs"

# --- locate godot binary ---
GODOT=""
for candidate in "${GODOT_BIN:-}" "/Applications/Godot.app/Contents/MacOS/Godot" "$(command -v godot || true)"; do
	if [[ -n "$candidate" && -x "$candidate" ]]; then
		GODOT="$candidate"
		break
	fi
done
if [[ -z "$GODOT" ]]; then
	echo "error: Godot binary not found." >&2
	echo "Set GODOT_BIN to your Godot executable, e.g.:" >&2
	echo "  export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot" >&2
	exit 1
fi

# --- locate adb ---
ADB=""
for candidate in "${ADB_BIN:-}" "$HOME/Library/Android/sdk/platform-tools/adb" "$(command -v adb || true)"; do
	if [[ -n "$candidate" && -x "$candidate" ]]; then
		ADB="$candidate"
		break
	fi
done
if [[ -z "$ADB" ]]; then
	echo "error: adb not found." >&2
	echo "Set ADB_BIN to your adb executable, e.g.:" >&2
	echo "  export ADB_BIN=\$HOME/Library/Android/sdk/platform-tools/adb" >&2
	exit 1
fi

# --- device check ---
if [[ "$("$ADB" get-state 2>/dev/null)" != "device" ]]; then
	echo "error: no Android device connected (adb get-state failed)." >&2
	echo "Check USB cable, enable USB debugging, then run: $ADB devices" >&2
	exit 1
fi

# --- ensure Android export settings (GUI editor resets java_sdk_path on save) ---
EDITOR_SETTINGS="$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"
JAVA_HOME_17="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
if [[ -n "$JAVA_HOME_17" && -f "$EDITOR_SETTINGS" ]]; then
	sed -i '' -E "s|^export/android/java_sdk_path = .*$|export/android/java_sdk_path = \"$JAVA_HOME_17\"|" "$EDITOR_SETTINGS"
fi

echo "godot: $GODOT ($("$GODOT" --version))"
echo "adb:   $ADB"
echo "device: $("$ADB" shell getprop ro.product.model 2>/dev/null || echo unknown)"

mkdir -p build
echo "exporting $PRESET_NAME -> $APK_PATH ..."
"$GODOT" --headless --path . --export-debug "$PRESET_NAME" "$APK_PATH"

echo "installing $APK_PATH ..."
"$ADB" install -r "$APK_PATH"

echo "done. launch with:"
echo "  $ADB shell monkey -p $PACKAGE_NAME -c android.intent.category.LAUNCHER 1"

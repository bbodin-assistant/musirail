GODOT ?= godot
ADB ?= adb
PYTHON ?= python3

PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(PROJECT_DIR)/build
APK ?= $(BUILD_DIR)/musirail-debug.apk
RELEASE_APK ?= $(BUILD_DIR)/musirail-release.apk
PRESET ?= Android
PACKAGE ?= io.github.bbodin.musirail
ACTIVITY ?= com.godot.game.GodotAppLauncher
PRIVATE_SONGS_DIR ?= $(PROJECT_DIR)/songs
DEVICE_SONGS_DIR ?= /sdcard/Download/Musirail

# Set DEVICE to an adb serial when more than one Android target is connected.
ADB_DEVICE = $(if $(DEVICE),-s $(DEVICE),)

.PHONY: demo-song test check-public check-godot export-android \
	export-android-debug export-android-release launch install-android \
	sync-private-songs run-android devices stop-android

launch: export-android-debug
	"$(MAKE)" --no-print-directory install-android
	"$(MAKE)" --no-print-directory sync-private-songs
	"$(MAKE)" --no-print-directory run-android

demo-song:
	"$(PYTHON)" "$(PROJECT_DIR)/tools/build_demo_song.py"

test:
	PYTHONPATH="$(PROJECT_DIR)/songs/tools" \
		"$(PYTHON)" -m unittest discover -s "$(PROJECT_DIR)/songs/tools/tests"

check-public:
	"$(PROJECT_DIR)/tools/check_public_tree.sh"

check-godot:
	"$(GODOT)" --headless --path "$(PROJECT_DIR)" --editor --quit

export-android: export-android-debug

export-android-debug: check-public
	mkdir -p "$(BUILD_DIR)"
	"$(GODOT)" --headless --path "$(PROJECT_DIR)" \
		--export-debug "$(PRESET)" "$(APK)"

export-android-release: check-public
	mkdir -p "$(BUILD_DIR)"
	"$(GODOT)" --headless --path "$(PROJECT_DIR)" \
		--export-release "$(PRESET)" "$(RELEASE_APK)"

install-android:
	"$(ADB)" $(ADB_DEVICE) install -r "$(APK)"

sync-private-songs:
	MUSIRAIL_ADB="$(ADB)" \
	MUSIRAIL_DEVICE="$(DEVICE)" \
	MUSIRAIL_PRIVATE_SONGS_DIR="$(PRIVATE_SONGS_DIR)" \
	MUSIRAIL_DEVICE_SONGS_DIR="$(DEVICE_SONGS_DIR)" \
		"$(PROJECT_DIR)/tools/push_private_songs.sh"

run-android:
	"$(ADB)" $(ADB_DEVICE) shell am force-stop "$(PACKAGE)"
	"$(ADB)" $(ADB_DEVICE) shell am start -n \
		"$(PACKAGE)/$(ACTIVITY)"

devices:
	"$(ADB)" devices -l

stop-android:
	"$(ADB)" $(ADB_DEVICE) shell am force-stop "$(PACKAGE)"

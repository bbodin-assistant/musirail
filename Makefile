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

# Set DEVICE to an adb serial when more than one Android target is connected.
ADB_DEVICE = $(if $(DEVICE),-s $(DEVICE),)

.PHONY: demo-song test check-public check-godot export-android \
	export-android-debug export-android-release launch install-android \
	run-android devices stop-android

launch: export-android-debug install-android run-android

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

run-android:
	"$(ADB)" $(ADB_DEVICE) shell am force-stop "$(PACKAGE)"
	"$(ADB)" $(ADB_DEVICE) shell am start -n \
		"$(PACKAGE)/$(ACTIVITY)"

devices:
	"$(ADB)" devices -l

stop-android:
	"$(ADB)" $(ADB_DEVICE) shell am force-stop "$(PACKAGE)"

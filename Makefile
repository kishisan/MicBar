APP_NAME = MicBar
BUNDLE_ID = com.kishisan.MicBar
BUILD_DIR = .build
APP_BUNDLE = $(APP_NAME).app

SOURCES = $(shell find Sources/MicBar -name '*.swift')
SDK = $(shell xcrun --show-sdk-path)

SWIFTC_FLAGS = \
	-O \
	-sdk $(SDK) \
	-target arm64-apple-macosx13.0 \
	-framework AppKit \
	-framework CoreAudio \
	-framework ServiceManagement \
	-swift-version 5

.PHONY: build app sign clean run install

build: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFTC_FLAGS) -o $@ $(SOURCES)

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo

sign: app
	codesign --force --deep --sign - \
		--entitlements Resources/MicBar.entitlements \
		--options runtime \
		$(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) $(APP_BUNDLE)

run: sign
	open $(APP_BUNDLE)

install: sign
	cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_BUNDLE)"

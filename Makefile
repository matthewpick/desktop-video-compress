.PHONY: generate build build-debug test clean install dmg bump-version

PROJECT_NAME = DesktopVideoCompress
APP_NAME = Desktop Video Compress
PROJECT_DIR = DesktopVideoCompress
BUILD_DIR = build
PROJECT_SPEC = $(PROJECT_DIR)/project.yml
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "dev")
DMG_NAME = DesktopVideoCompress-$(VERSION).dmg

# Generate the Xcode project from project.yml (the source of truth).
# The .xcodeproj is not committed; regenerate it before any build.
generate:
	xcodegen generate --spec $(PROJECT_SPEC)

build: generate
	xcodebuild -project $(PROJECT_DIR)/$(PROJECT_NAME).xcodeproj \
		-scheme $(PROJECT_NAME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build

build-debug: generate
	xcodebuild -project $(PROJECT_DIR)/$(PROJECT_NAME).xcodeproj \
		-scheme $(PROJECT_NAME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		build

test: generate
	xcodebuild test \
		-project $(PROJECT_DIR)/$(PROJECT_NAME).xcodeproj \
		-scheme $(PROJECT_NAME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR)

install: build
	@echo "Stopping any running copy..."
	@osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null || true
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"
	@echo "Launch with: open -a \"$(APP_NAME)\""

dmg: build
	@echo "Creating DMG: $(DMG_NAME)"
	@rm -rf dmg-contents $(DMG_NAME)
	@mkdir -p dmg-contents
	@cp -R "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app" dmg-contents/
	@if command -v create-dmg &> /dev/null; then \
		create-dmg \
			--volname "Desktop Video Compress" \
			--window-pos 200 120 \
			--window-size 600 400 \
			--icon-size 100 \
			--icon "$(APP_NAME).app" 150 185 \
			--hide-extension "$(APP_NAME).app" \
			--app-drop-link 450 185 \
			"$(DMG_NAME)" \
			dmg-contents/ || true; \
	else \
		hdiutil create -volname "Desktop Video Compress" -srcfolder dmg-contents -ov -format UDZO "$(DMG_NAME)"; \
	fi
	@rm -rf dmg-contents
	@echo "Created: $(DMG_NAME)"
	@shasum -a 256 "$(DMG_NAME)"

clean:
	rm -rf $(BUILD_DIR) dmg-contents *.dmg

# Bump version: make bump-version V=0.1.1
bump-version:
ifndef V
	$(error V is required. Usage: make bump-version V=0.1.1)
endif
	@sed -i '' 's/MARKETING_VERSION: .*/MARKETING_VERSION: "$(V)"/' $(PROJECT_SPEC)
	@$(MAKE) generate
	@echo "Version bumped to $(V)"
	@echo ""
	@echo "Next steps:"
	@echo "  git add -A && git commit -m 'Bump version to $(V)'"
	@echo "  git tag v$(V) && git push origin main --tags"

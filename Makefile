APP_BUNDLE = build/FanControl.app

# Where the compiled products land. A plain `swift build -c release` writes to
# .build/release; a multi-arch build writes somewhere else entirely, so the
# bundle step takes this as a variable.
BIN_DIR ?= .build/release
UNIVERSAL_BIN_DIR = .build/apple/Products/Release

# Stamped into the released app and the archive name. Overridden by CI with the
# git tag; `dev` is the local default.
VERSION ?= dev
DIST_NAME = FanControl-$(VERSION)
DIST_DIR = build/$(DIST_NAME)

.PHONY: build release universal bundle app install install-daemon install-app \
        uninstall dist status clean

build:
	swift build

release:
	swift build -c release

# Both architectures in one set of binaries, so a release built on an Apple
# Silicon runner still runs on Intel.
universal:
	swift build -c release --arch arm64 --arch x86_64

# Assemble the menu bar app bundle from whatever is in BIN_DIR.
bundle:
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BIN_DIR)/FanControlApp $(APP_BUNDLE)/Contents/MacOS/FanControlApp
	cp Resources/AppInfo.plist $(APP_BUNDLE)/Contents/Info.plist
ifneq ($(VERSION),dev)
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
		$(APP_BUNDLE)/Contents/Info.plist
endif
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

app: release
	$(MAKE) bundle

# Full install: root daemon + app in /Applications.
install: release app install-daemon install-app

install-daemon:
	sudo scripts/install-daemon.sh

install-app:
	rm -rf "/Applications/FanControl.app"
	cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed /Applications/FanControl.app — open it from Spotlight or:"
	@echo "  open /Applications/FanControl.app"

uninstall:
	sudo scripts/uninstall-daemon.sh
	rm -rf "/Applications/FanControl.app"

# Universal, downloadable archive: app + CLI + daemon + installer.
dist: universal
	$(MAKE) bundle BIN_DIR=$(UNIVERSAL_BIN_DIR)
	rm -rf $(DIST_DIR) build/$(DIST_NAME).zip
	mkdir -p $(DIST_DIR)/bin $(DIST_DIR)/scripts $(DIST_DIR)/Resources
	cp -R $(APP_BUNDLE) $(DIST_DIR)/
	cp $(UNIVERSAL_BIN_DIR)/fanctl $(UNIVERSAL_BIN_DIR)/fanctld $(DIST_DIR)/bin/
	# The linker leaves these ad-hoc "linker-signed", which codesign --verify
	# rejects. Sign them properly so the archive can be checked as a whole.
	codesign --force --sign - $(DIST_DIR)/bin/fanctl $(DIST_DIR)/bin/fanctld
	cp Resources/io.github.jbforge.fanctld.plist $(DIST_DIR)/Resources/
	cp scripts/install-daemon.sh scripts/uninstall-daemon.sh $(DIST_DIR)/scripts/
	cp scripts/install.sh scripts/uninstall.sh $(DIST_DIR)/
	cp INSTALL.md LICENSE $(DIST_DIR)/
	chmod +x $(DIST_DIR)/install.sh $(DIST_DIR)/uninstall.sh \
		$(DIST_DIR)/scripts/*.sh $(DIST_DIR)/bin/*
	# ditto preserves the bundle's code signature; `zip` does not.
	cd build && ditto -c -k --sequesterRsrc --keepParent $(DIST_NAME) $(DIST_NAME).zip
	@echo "Built build/$(DIST_NAME).zip"

status:
	.build/release/fanctl status || swift run fanctl status

clean:
	rm -rf .build build

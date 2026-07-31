APP_BUNDLE = build/FanControl.app

.PHONY: build release app install install-daemon install-app uninstall status clean

build:
	swift build

release:
	swift build -c release

# Assemble the menu bar app bundle.
app: release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp .build/release/FanControlApp $(APP_BUNDLE)/Contents/MacOS/FanControlApp
	cp Resources/AppInfo.plist $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

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

status:
	.build/release/fanctl status || swift run fanctl status

clean:
	rm -rf .build build

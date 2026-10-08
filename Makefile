APP := build/Build/Products/Release/minmd.app

.PHONY: project build install open clean

project:
	xcodegen generate

build: project
	xcodebuild -project minmd.xcodeproj -scheme minmd -configuration Release \
		-derivedDataPath build -quiet build

# Installs to /Applications and registers the Quick Look extension.
install: build
	rm -rf /Applications/minmd.app
	cp -R $(APP) /Applications/
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/minmd.app
	pluginkit -a /Applications/minmd.app/Contents/PlugIns/MinMDQuickLook.appex
	qlmanage -r >/dev/null 2>&1 || true
	@echo "Installed /Applications/minmd.app"

open: project
	open minmd.xcodeproj

clean:
	rm -rf build minmd.xcodeproj

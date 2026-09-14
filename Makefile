# Mac app: Release build, DMG, install to /Applications, GitHub release.
# Signed with the Apple Development identity: runs on your own Macs; other people's need Developer ID + notarization.

VERSION := $(shell awk '/MARKETING_VERSION/ {gsub(/"/, "", $$2); print $$2}' project.yml)
APP := build/Build/Products/Release/Niim.app
DMG := build/Niim-$(VERSION).dmg
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: project release dmg deploy publish test clean

project:
	xcodegen generate

release: project
	xcodebuild -project Niim.xcodeproj -scheme Niim -configuration Release -destination 'generic/platform=macOS' \
		-derivedDataPath build -allowProvisioningUpdates -quiet build

dmg: release
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	ditto $(APP) build/dmg/Niim.app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Niim $(VERSION)" -srcfolder build/dmg -format UDZO -ov $(DMG)

deploy: release
	pkill -x Niim || true
	rm -rf /Applications/Niim.app
	ditto $(APP) /Applications/Niim.app
	$(LSREGISTER) -f /Applications/Niim.app
	open /Applications/Niim.app

# Tags v$(VERSION) (from MARKETING_VERSION in project.yml) and publishes the DMG as a GitHub release.
publish: dmg
	git diff --quiet HEAD || { echo "Commit your changes before publishing"; exit 1; }
	git tag -a v$(VERSION) -m "Niim $(VERSION)"
	git push origin main v$(VERSION)
	gh release create v$(VERSION) $(DMG) --title "Niim $(VERSION)" --generate-notes

test:
	swift test --package-path NiimKit

clean:
	rm -rf build

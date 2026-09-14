# Mac: Developer ID-signed Release build, notarized DMG, install to /Applications, GitHub release.
# iPhone: build, install and launch on a paired phone.

VERSION := $(shell awk '/MARKETING_VERSION/ {gsub(/"/, "", $$2); print $$2}' project.yml)
ARCHIVE := build/Niim.xcarchive
APP := build/export/Niim.app
DMG := build/Niim-$(VERSION).dmg
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Keychain profile for notarytool, created once with `xcrun notarytool store-credentials` (see README)
NOTARY_PROFILE ?= niim-notary
# iPhone name or identifier; defaults to the first paired iPhone
DEVICE ?= $(shell f=$$(mktemp); xcrun devicectl list devices -j $$f >/dev/null 2>&1; \
	jq -r '[.result.devices[] | select(.hardwareProperties.deviceType == "iPhone" and .connectionProperties.pairingState == "paired")][0].identifier // empty' $$f; rm -f $$f)

.PHONY: project release dmg notarize deploy publish clean-tree iphone test clean

project:
	xcodegen generate

release: project
	xcodebuild -project Niim.xcodeproj -scheme Niim -configuration Release -destination 'generic/platform=macOS' \
		-archivePath $(ARCHIVE) -derivedDataPath build -allowProvisioningUpdates -quiet archive
	rm -rf build/export
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath build/export -exportOptionsPlist Config/ExportOptions.plist \
		-allowProvisioningUpdates -quiet

dmg: release
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	ditto $(APP) build/dmg/Niim.app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Niim $(VERSION)" -srcfolder build/dmg -format UDZO -ov $(DMG)
	codesign --sign "Developer ID Application" --timestamp $(DMG)

notarize: dmg
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)

deploy: release
	pkill -x Niim || true
	rm -rf /Applications/Niim.app
	ditto $(APP) /Applications/Niim.app
	$(LSREGISTER) -f /Applications/Niim.app
	open /Applications/Niim.app

clean-tree:
	git diff --quiet HEAD || { echo "Commit your changes before publishing"; exit 1; }

# Tags v$(VERSION) (from MARKETING_VERSION in project.yml) and publishes the notarized DMG as a GitHub release.
publish: clean-tree notarize
	git tag -a v$(VERSION) -m "Niim $(VERSION)"
	git push origin main v$(VERSION)
	gh release create v$(VERSION) $(DMG) --title "Niim $(VERSION)" --generate-notes

iphone: project
	@test -n "$(DEVICE)" || { echo "No paired iPhone found; pass DEVICE=<name>"; exit 1; }
	xcodebuild -project Niim.xcodeproj -scheme Niim -configuration Release -destination 'generic/platform=iOS' \
		-derivedDataPath build/ios -allowProvisioningUpdates -quiet build
	dev="$(DEVICE)"; xcrun devicectl device install app --device "$$dev" build/ios/Build/Products/Release-iphoneos/Niim.app && \
		xcrun devicectl device process launch --device "$$dev" io.lyx.niim

test:
	swift test --package-path NiimKit

clean:
	rm -rf build

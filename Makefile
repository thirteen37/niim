# Mac app: Release build, installed to /Applications.
# Signed with the Apple Development identity (fine on this Mac; distributing needs Developer ID + notarization).

APP := build/Build/Products/Release/Niim.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: project release deploy test clean

project:
	xcodegen generate

release: project
	xcodebuild -project Niim.xcodeproj -scheme Niim -configuration Release -destination 'generic/platform=macOS' \
		-derivedDataPath build -allowProvisioningUpdates -quiet build

deploy: release
	pkill -x Niim || true
	rm -rf /Applications/Niim.app
	ditto $(APP) /Applications/Niim.app
	$(LSREGISTER) -f /Applications/Niim.app
	open /Applications/Niim.app

test:
	swift test --package-path NiimKit

clean:
	rm -rf build

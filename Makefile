PROJECT := Colorbee.xcodeproj
SCHEME  := Colorbee
DERIVED := build
APP     := $(DERIVED)/Build/Products/Debug/Colorbee.app

.PHONY: gen build test core run open clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

core:
	cd Packages/ColorbeeCore && swift test

test: core build

run: build
	open $(APP)

open: gen
	open $(PROJECT)

clean:
	rm -rf $(DERIVED) Packages/ColorbeeCore/.build $(PROJECT)

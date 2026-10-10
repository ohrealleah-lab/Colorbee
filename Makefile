PROJECT := Colorbee.xcodeproj
SCHEME  := Colorbee
DERIVED := build
APP     := $(DERIVED)/Build/Products/Debug/Colorbee.app
BENCH   := $(DERIVED)/Build/Products/Release/Colorbee.app/Contents/MacOS/Colorbee -ColorbeeBenchmark YES -ApplePersistenceIgnoreState YES

.PHONY: gen build test core perf run bench beta help-index help-shots open clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

core:
	cd Packages/ColorbeeCore && swift test

test: core build

# Release-only time limits and the 8000x8000 soak test (AC-27, NFR-7). Takes a few minutes.
perf:
	cd Packages/ColorbeeCore && swift test -c release --no-parallel --filter "SoakTests|PerformanceTests"

# The help book's search index (FR-14.6). Run after changing a help page; the index is committed.
HELP := Help/Colorbee.help/Contents/Resources/en.lproj
help-index:
	hiutil -I corespotlight -Caf $(HELP)/Colorbee.cshelpindex -s en $(HELP)
	hiutil -I corespotlight -Fvf $(HELP)/Colorbee.cshelpindex

# Guided screenshots for the help book: Colorbee sets up each scene, Leah takes the picture. Brings windows to the front.
help-shots: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build
	Scripts/help-shots.sh

# Signed, notarized beta zip for testers in build/Beta. Uses the keychain; may ask for its password.
beta:
	Scripts/make-beta.sh

# Release, so it runs at real speed (Debug pixel loops are ~50x slower).
run: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build
	open $(DERIVED)/Build/Products/Release/Colorbee.app

bench: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build
	@echo "== Default 1920x1080 canvas, 5 px brush =="
	@$(BENCH)
	@echo "== Worst case: 8000x8000 canvas, 50 px brush =="
	@$(BENCH) -BenchmarkCanvas 8000 -BenchmarkBrush 50

open: gen
	open $(PROJECT)

clean:
	rm -rf $(DERIVED) Packages/ColorbeeCore/.build $(PROJECT)

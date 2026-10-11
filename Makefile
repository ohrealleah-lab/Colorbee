PROJECT := Colorbee.xcodeproj
SCHEME  := Colorbee
DERIVED := build
APP     := $(DERIVED)/Build/Products/Debug/Colorbee.app
BENCH   := $(DERIVED)/Build/Products/Release/Colorbee.app/Contents/MacOS/Colorbee -ColorbeeBenchmark YES -ApplePersistenceIgnoreState YES

.PHONY: gen build test core app-test coverage perf run bench beta help help-index help-shots open clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

core:
	cd Packages/ColorbeeCore && swift test

test: core app-test

# The app tests (Tests/ColorbeeTests) build the app too. They run inside Colorbee, which starts hidden: no Dock icon,
# windows or focus. One process: parallel testing would start several copies of the app.
app-test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -parallel-testing-enabled NO -quiet test

# Line coverage of the core and the app (the app tests run with coverage on). Separate from `make test`: slower.
COVERAGE := $(DERIVED)/Coverage.xcresult
coverage: gen
	cd Packages/ColorbeeCore && swift test --enable-code-coverage -q
	@echo "== Core =="
	@cd Packages/ColorbeeCore && xcrun llvm-cov report .build/debug/ColorbeeCorePackageTests.xctest/Contents/MacOS/ColorbeeCorePackageTests \
		-instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex='(\.build|Tests)/' | tail -1
	rm -rf $(COVERAGE)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -parallel-testing-enabled NO -quiet \
		-enableCodeCoverage YES -resultBundlePath $(COVERAGE) test
	@echo "== App =="
	@xcrun xccov view --report --only-targets $(COVERAGE) | grep -E 'Colorbee.app'
	@xcrun xccov view --report --files-for-target Colorbee.app $(COVERAGE) | grep -E 'Editor\.swift'

# Release-only time limits and the 8000x8000 soak test (AC-27, NFR-7). Takes a few minutes.
perf:
	cd Packages/ColorbeeCore && swift test -c release --no-parallel --filter "SoakTests|PerformanceTests"

# The help book's Menus and Keyboard Shortcuts pages, generated from Colorbee's own menus (no window opens), then the
# search index. Run after adding, renaming or re-keying a menu command.
help: build
	build/Build/Products/Debug/Colorbee.app/Contents/MacOS/Colorbee -ApplePersistenceIgnoreState YES -ColorbeeDumpMenus build/menus.json
	python3 -I Scripts/help-pages.py build/menus.json $(HELP)
	$(MAKE) help-index

# The help book's search index (FR-14.6). Run after changing a help page; the index is committed.
HELP := Help/Colorbee.help/Contents/Resources/en.lproj
help-index:
	hiutil -I corespotlight -Caf $(HELP)/Colorbee.cshelpindex -s en $(HELP)
	hiutil -I corespotlight -Fvf $(HELP)/Colorbee.cshelpindex
	@# A new version each time, so macOS's help cache (helpd) shows the changed pages, also for people who update.
	@v=$$(date +%Y%m%d%H%M); \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$v" -c "Set :CFBundleShortVersionString $$v" Help/Colorbee.help/Contents/Info.plist; \
	echo "Help book version $$v"

# Guided screenshots for the help book: Colorbee sets up each scene, Leah takes the picture. Brings windows to the front.
help-shots: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build
	SCENES="$(SCENES)" Scripts/help-shots.sh

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

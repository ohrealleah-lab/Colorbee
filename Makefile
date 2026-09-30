PROJECT := Colorbee.xcodeproj
SCHEME  := Colorbee
DERIVED := build
APP     := $(DERIVED)/Build/Products/Debug/Colorbee.app
BENCH   := $(DERIVED)/Build/Products/Release/Colorbee.app/Contents/MacOS/Colorbee -ColorbeeBenchmark YES -ApplePersistenceIgnoreState YES

.PHONY: gen build test core run bench open clean

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

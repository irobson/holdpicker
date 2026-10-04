APP_NAME := HoldPicker
CONFIG   ?= release

.PHONY: build run test bundle open install clean

## Build the debug binary.
build:
	swift build

## Run straight from the package (no app bundle). Good for development.
run:
	swift run $(APP_NAME)

## Run the unit tests for the core logic.
test:
	scripts/test.sh

## Produce build/$(APP_NAME).app (release by default, CONFIG=debug to override).
bundle:
	CONFIG=$(CONFIG) scripts/bundle.sh

## Bundle and launch the app.
open: bundle
	open build/$(APP_NAME).app

## Copy the last bundle into /Applications without rebuilding.
## Rebuilding changes the ad-hoc signature and invalidates privacy grants,
## so this deliberately does not depend on `bundle`.
install:
	@test -d build/$(APP_NAME).app || { echo "Run 'make bundle' first."; exit 1; }
	-osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null
	rm -rf /Applications/$(APP_NAME).app
	cp -R build/$(APP_NAME).app /Applications/
	open /Applications/$(APP_NAME).app

## Remove all build products.
clean:
	rm -rf .build build

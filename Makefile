APP_NAME := HoldShot
CONFIG   ?= release

.PHONY: build run test bundle open clean

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

## Remove all build products.
clean:
	rm -rf .build build

APP_NAME := TedCat
BUNDLE_ID := dev.tedcat.TedCat
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

## Copy the last bundle into /Applications without rebuilding, and leave it closed.
## Rebuilding changes the ad-hoc signature and invalidates privacy grants,
## so this deliberately does not depend on `bundle`. It also does not launch
## the app: permissions must be granted while TedCat is NOT running
## (changing them while its event tap is live can block every click).
install:
	@test -d build/$(APP_NAME).app || { echo "Run 'make bundle' first."; exit 1; }
	-osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null
	@# Quitting is asynchronous (it may be finishing a recording). Wait up to 10 s.
	@for i in $$(seq 1 100); do pgrep -x $(APP_NAME) >/dev/null || break; sleep 0.1; done
	@if pgrep -x $(APP_NAME) >/dev/null; then echo "$(APP_NAME) is still running; quit it and retry."; exit 1; fi
	rm -rf /Applications/$(APP_NAME).app
	cp -R build/$(APP_NAME).app /Applications/
	@echo ""
	@echo "Installed. $(APP_NAME) is NOT running."
	@echo "After a rebuild the old grants are stale; reset them first (app closed):"
	@echo "  tccutil reset Accessibility $(BUNDLE_ID)"
	@echo "  tccutil reset ScreenCapture $(BUNDLE_ID)"
	@echo "Then, before opening it:"
	@echo "  1. System Settings > Privacy & Security > Accessibility: turn $(APP_NAME) on"
	@echo "     (if it is not listed, click + and choose /Applications/$(APP_NAME).app)."
	@echo "  2. Same place, Screen & System Audio Recording (Screen Recording on macOS 14):"
	@echo "     turn $(APP_NAME) on, or add it with +."
	@echo "  3. Quit System Settings, then open $(APP_NAME) from Spotlight."

## Remove all build products.
clean:
	rm -rf .build build

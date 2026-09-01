APP      := build/Toe.app
BUNDLEID := com.clifmeister.toe
AGENT    := $(HOME)/Library/LaunchAgents/$(BUNDLEID).plist

.PHONY: all build test bundle run install uninstall dev-cert reset-perms start-at-login stop-at-login example-config icon clean

all: bundle

build:
	swift build -c release

## Layout engine test suite. XCTest ships with Xcode, not the Command Line Tools, so the
## suite is a plain executable and runs anywhere Swift does.
test:
	@swift run -c debug toe-selftest

bundle: test
	@./scripts/bundle.sh release

## Build and launch in place, replacing any running copy.
run: bundle
	@pkill -x toe 2>/dev/null || true
	@# SIGTERM is asynchronous, and toe handles it rather than dying on the spot: it unstashes
	@# every hidden workspace and takes down the event tap first. Opening the new copy while the
	@# old one is still on its way out makes LaunchServices refuse the launch with -600, so wait
	@# for the process to actually be gone. Bounded, so a wedged toe cannot hang the build.
	@for _ in $$(seq 50); do pgrep -x toe >/dev/null || break; sleep 0.1; done
	@pgrep -x toe >/dev/null && { echo "a previous toe will not exit — kill -9 it and retry"; exit 1; } || true
	@open $(APP)
	@echo "toe running — look for it in the menu bar"

install: bundle
	@pkill -x toe 2>/dev/null || true
	@rm -rf /Applications/Toe.app
	@cp -R $(APP) /Applications/Toe.app
	@echo "installed /Applications/Toe.app — run 'make start-at-login' to launch it at login"

uninstall: stop-at-login
	@pkill -x toe 2>/dev/null || true
	@rm -rf /Applications/Toe.app
	@echo "removed /Applications/Toe.app"

## One-time: a stable self-signed signing identity, so macOS stops re-asking for
## Accessibility after every rebuild. Prompts once for your login password.
dev-cert:
	@./scripts/dev-cert.sh

## macOS keys Accessibility grants to the code signature, and an ad-hoc signature changes on
## every build. Run this after a rebuild if hotkeys or window moves stop working.
reset-perms:
	@tccutil reset Accessibility $(BUNDLEID) || true
	@echo "re-grant Accessibility for toe, then relaunch"

start-at-login:
	@mkdir -p $(dir $(AGENT))
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>Label</key><string>$(BUNDLEID)</string>' \
	  '  <key>ProgramArguments</key><array><string>/Applications/Toe.app/Contents/MacOS/toe</string></array>' \
	  '  <key>RunAtLoad</key><true/>' \
	  '  <key>KeepAlive</key><false/>' \
	  '</dict></plist>' > $(AGENT)
	@launchctl unload $(AGENT) 2>/dev/null || true
	@launchctl load $(AGENT)
	@echo "toe will start at login"

stop-at-login:
	@launchctl unload $(AGENT) 2>/dev/null || true
	@rm -f $(AGENT)

## Redraw Resources/Toe.icns. Deliberately not a dependency of `bundle`: the committed .icns
## is what ships, and regenerating a binary file on every build would churn the tree.
icon:
	@swift scripts/make-icon.swift

## Regenerate toe.example.toml from the default baked into the binary.
example-config: build
	@swift run -c release toe --print-default-config > toe.example.toml
	@echo "wrote toe.example.toml"

clean:
	@rm -rf .build build

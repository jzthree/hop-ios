# hop-ios — build, test, and install without remembering flags.
#   make test       run the unit suite in the simulator
#   make install    build signed and install to the connected iPhone
#   make sim        install + launch in the simulator (auth via daemon token)
#   make shot       screenshot the simulator to /tmp/hop-ios.png
DEVICE ?= FA720813-48B6-5E57-984D-C76733368A9D
SIMNAME ?= iPhone 17 Pro
SIM ?= 56F2687C-0938-490F-ABC4-18461A4D8F36
BUNDLE = io.zhoulab.hop.spike
PROJECT = HopSpike.xcodeproj
SCHEME = HopSpike
APP = build/Build/Products/Debug-iphoneos/HopSpike.app
SIMAPP = build-sim/Build/Products/Debug-iphonesimulator/HopSpike.app
# The daemon accepts its own session secret as a bearer token / cookie, which
# is how the simulator gets past TOTP during development.
TOKEN = $(shell python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.hop2/.tunnel-state')))['sessionSecret'])" 2>/dev/null)

.PHONY: gen build test sim install shot clean

gen:
	xcodegen

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
	  -derivedDataPath build build

test: gen
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO

simbuild: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO build

# Wi-Fi installs are flaky (DeviceLocked / immediate disconnect): retry, and
# use a cable for a one-shot install.
install: build
	@for i in $$(seq 1 15); do \
	  out=$$(xcrun devicectl device install app --device $(DEVICE) "$(APP)" 2>&1); \
	  if echo "$$out" | grep -qE "App installed|installationURL|Complete!"; then echo "installed (attempt $$i)"; exit 0; fi; \
	  echo "attempt $$i: $$(echo "$$out" | grep -oE 'DeviceLocked|disconnected immediately' | head -1)"; sleep 8; \
	done; echo "install failed — unlock the phone or plug in a cable"; exit 1

sim: simbuild
	-xcrun simctl boot $(SIM) 2>/dev/null
	-xcrun simctl terminate $(SIM) $(BUNDLE) 2>/dev/null
	xcrun simctl install $(SIM) $(SIMAPP)
	SIMCTL_CHILD_HOP_DEV_COOKIE=$(TOKEN) $(if $(OPEN),SIMCTL_CHILD_HOP_DEV_OPEN=$(OPEN),) \
	  $(if $(GROUP),SIMCTL_CHILD_HOP_DEV_GROUP=$(GROUP),) $(if $(SCOPE),SIMCTL_CHILD_HOP_DEV_SCOPE=$(SCOPE),) \
	  xcrun simctl launch $(SIM) $(BUNDLE)

shot:
	xcrun simctl io $(SIM) screenshot /tmp/hop-ios.png && echo "wrote /tmp/hop-ios.png"

clean:
	rm -rf build build-sim $(PROJECT)

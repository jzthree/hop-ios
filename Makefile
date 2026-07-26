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
APP = build/Build/Products/Release-iphoneos/HopSpike.app
DEBUG_APP = build/Build/Products/Debug-iphoneos/HopSpike.app
SIMAPP = build-sim/Build/Products/Debug-iphonesimulator/HopSpike.app
# The daemon accepts its own session secret as a bearer token / cookie, which
# is how the simulator gets past TOTP during development.
# Every install should be identifiable on the device — "1.0 (1)" forever meant
# you couldn't tell whether the phone had the build with the fix in it.
BUILDNO = $(shell git rev-list --count HEAD)
GITDESC = $(shell git describe --always --dirty)
VERSION_FLAGS = CURRENT_PROJECT_VERSION=$(BUILDNO) HOP_GIT_DESCRIBE=$(GITDESC)

TOKEN = $(shell python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.hop2/.tunnel-state')))['sessionSecret'])" 2>/dev/null)

.PHONY: gen build test uitest sim install shot archive testflight clean

gen:
	xcodegen

# Release, not Debug. Swift Debug is -Onone: the terminal parser, the scroll
# maths and SwiftUI's diffing all run unoptimised, and this is the build that
# lives on a phone all day. APS_ENVIRONMENT is forced back to development
# because a locally-signed install is a development one — Release only flips it
# to production for TestFlight, and a production token cannot be pushed to by a
# development APNs connection.
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
	  -derivedDataPath build $(VERSION_FLAGS) APS_ENVIRONMENT=development build

# The unoptimised build, for when something needs a debugger attached.
build-debug: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
	  -derivedDataPath build $(VERSION_FLAGS) build

install-debug: build-debug
	@xcrun devicectl device install app --device $(DEVICE) "$(DEBUG_APP)"

test: gen
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO

# Real gestures against the real app: the only automated way to catch the
# class of bug (no scrolling, taps not focusing) that unit tests and
# screenshots both miss. TEST_RUNNER_ prefixed vars reach the test runner.
# Full output is kept, always. These tests drive a LIVE fleet, so a rare flake
# is expected — and a flake you can't name is a flake you can't fix. Filtering
# xcodebuild's output through grep at the call site loses the test's identity
# exactly when it matters.
uitest: gen
	@TEST_RUNNER_HOP_DEV_COOKIE=$(TOKEN) xcodebuild test \
	  -project $(PROJECT) -scheme HopSpikeUI \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO $(VERSION_FLAGS) > build-sim/uitest.log 2>&1; \
	  status=$$?; \
	  grep -E "Executed [0-9]+ tests" build-sim/uitest.log | tail -1; \
	  grep -E "' failed \(|XCTAssert" build-sim/uitest.log | head -5; \
	  echo "full log: build-sim/uitest.log"; exit $$status

simbuild: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO $(VERSION_FLAGS) build

# Wi-Fi installs are flaky (DeviceLocked / immediate disconnect): retry, and
# use a cable for a one-shot install.
install: build
	@for i in $$(seq 1 15); do \
	  out=$$(xcrun devicectl device install app --device $(DEVICE) "$(APP)" 2>&1); \
	  if echo "$$out" | grep -qE "App installed|installationURL|Complete!"; then echo "installed (attempt $$i)"; exit 0; fi; \
	  echo "attempt $$i: $$(echo "$$out" | grep -oE 'DeviceLocked|disconnected immediately' | head -1)"; sleep 8; \
	done; echo "install failed — unlock the phone or plug in a cable"; exit 1

# Delivery over cellular. `make install` needs the phone on the Mac's network;
# TestFlight installs from anywhere, including 5G, and is the same explicit App
# ID that Push needs — so it unblocks APNs at the same time.
#
# REQUIRES, once, in Xcode or the developer portal (account-level, so not done
# from here): register io.zhoulab.hop.spike as an explicit App ID, create the
# app record in App Store Connect, and let Xcode make a distribution
# certificate. After that `make testflight` is the whole loop; internal testers
# get the build as soon as processing finishes, with no review.
# The App Store Connect API key does double duty: it lets xcodebuild CREATE the
# distribution profile (Xcode itself has no account signed in — "No Accounts" is
# why plain -allowProvisioningUpdates fails) and then upload the build.
#
#   make testflight ISSUER=<issuer-uuid>
#
# ISSUER comes from App Store Connect -> Users and Access -> Integrations ->
# App Store Connect API, shown as "Issuer ID" above the key list. The key
# itself (AuthKey_CCFL4WD4V4.p8) is already in ~/.appstoreconnect/private_keys.
ASC_KEY_ID ?= CCFL4WD4V4
ASC_KEY_PATH ?= $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8
ASC_AUTH = -authenticationKeyPath $(ASC_KEY_PATH) \
           -authenticationKeyID $(ASC_KEY_ID) \
           -authenticationKeyIssuerID $(ISSUER)

archive: gen
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
	  -archivePath build/HopSpike.xcarchive $(VERSION_FLAGS)

testflight: archive
	@test -n "$(ISSUER)" || (echo "ISSUER=<uuid> required — see the comment above this target"; exit 1)
	xcodebuild -exportArchive -archivePath build/HopSpike.xcarchive \
	  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates \
	  $(ASC_AUTH) -exportPath build/export

sim: simbuild
	-xcrun simctl boot $(SIM) 2>/dev/null
	-xcrun simctl terminate $(SIM) $(BUNDLE) 2>/dev/null
	xcrun simctl install $(SIM) $(SIMAPP)
	SIMCTL_CHILD_HOP_DEV_COOKIE=$(TOKEN) $(if $(OPEN),SIMCTL_CHILD_HOP_DEV_OPEN=$(OPEN),) \
	  $(if $(GROUP),SIMCTL_CHILD_HOP_DEV_GROUP=$(GROUP),) $(if $(SCOPE),SIMCTL_CHILD_HOP_DEV_SCOPE=$(SCOPE),) \
	  $(if $(SHEET),SIMCTL_CHILD_HOP_DEV_SHEET=$(SHEET),) $(if $(FILTER),SIMCTL_CHILD_HOP_DEV_FILTER=$(FILTER),) $(if $(OFFLINE),SIMCTL_CHILD_HOP_DEV_OFFLINE=$(OFFLINE),) $(if $(COMPACT),SIMCTL_CHILD_HOP_DEV_COMPACT=$(COMPACT),) $(if $(ATTN),SIMCTL_CHILD_HOP_DEV_ATTENTION=$(ATTN),) $(if $(GONE),SIMCTL_CHILD_HOP_DEV_GONE=$(GONE),) \
	  xcrun simctl launch $(SIM) $(BUNDLE)

# The two lenses that found real bugs without a phone: the compiler's complete
# concurrency checking (a race on the socket's retired-generation guard, #112b)
# and Thread Sanitizer over the tests that actually open, close and reopen
# sockets. Neither is on by default; both are cheap to re-run.
strict:
	@xcodebuild -project $(PROJECT) -scheme HopSpike \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-strict CODE_SIGNING_ALLOWED=NO \
	  SWIFT_STRICT_CONCURRENCY=complete build > build-strict.log 2>&1; \
	  echo "warnings in our sources: $$(grep -cE 'Sources/HopSpike/.*warning:' build-strict.log)"; \
	  grep -E "Sources/HopSpike/.*warning:" build-strict.log | sed 's/.*Sources/Sources/' | sort -u

tsan: gen
	@TEST_RUNNER_HOP_DEV_COOKIE=$(TOKEN) xcodebuild test \
	  -project $(PROJECT) -scheme HopSpikeUI \
	  -destination 'platform=iOS Simulator,name=$(SIMNAME)' \
	  -derivedDataPath build-tsan CODE_SIGNING_ALLOWED=NO -enableThreadSanitizer YES \
	  -only-testing:HopSpikeUITests/ScrollUITests/testReconnectKeepsTheSessionUsable \
	  -only-testing:HopSpikeUITests/ScrollUITests/testSwitchSessionFromTheTitleMenu \
	  -only-testing:HopSpikeUITests/ScrollUITests/testDragOnAgentSessionKeepsSessionUsable \
	  > build-tsan.log 2>&1; \
	  echo "races: $$(grep -c 'WARNING: ThreadSanitizer' build-tsan.log)"; \
	  grep -E "Executed [0-9]+ tests" build-tsan.log | tail -1

shot:
	xcrun simctl io $(SIM) screenshot /tmp/hop-ios.png && echo "wrote /tmp/hop-ios.png"

clean:
	rm -rf build build-sim $(PROJECT)

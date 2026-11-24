GO ?= go
PYTHON ?= python3
GOFMT := $(shell dirname "$(shell command -v $(GO))")/gofmt
VERSION ?= 0.1.2
SIGN_IDENTITY ?=
REVISION := $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo uncommitted)
DIRTY := $(shell test -z "$$(git status --porcelain)" || echo -dirty)
LDFLAGS := -X main.version=$(VERSION) -X main.revision=$(REVISION)$(DIRTY)
BIN := .build/ghoops
INSTALLED := $(HOME)/.local/bin/ghealth

.PHONY: check fmt fmt-check vet test race vulncheck signing-contract adapter-check goop-lint build smoke install keychain-check keychain-update-check live clean

check: fmt-check vet test race signing-contract adapter-check build smoke goop-lint

fmt:
	$(GOFMT) -w cmd internal

fmt-check:
	@test -z "$$($(GOFMT) -l cmd internal)" || { $(GOFMT) -l cmd internal; exit 1; }

vet:
	GOTOOLCHAIN=local $(GO) vet ./...

test:
	GOTOOLCHAIN=local $(GO) test -count=1 -timeout=90s ./...

race:
	CGO_ENABLED=1 GOTOOLCHAIN=local $(GO) test -race -count=1 -timeout=600s ./...

vulncheck:
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 GOTOOLCHAIN=local $(GO) run golang.org/x/vuln/cmd/govulncheck@v1.10.0 ./cmd/ghoops

signing-contract:
	$(PYTHON) scripts/signing_contract_test.py
	$(PYTHON) scripts/installation_lifecycle_test.py

adapter-check:
	python3 scripts/morning_summary_test.py
	python3 -I scripts/v2_shape_test.py
	python3 -I scripts/goop_preview_fixtures_test.py
	python3 -I scripts/goop_lint_test.py
	python3 -I scripts/edit_fixture_store_test.py
	python3 -I scripts/load_fixture_store_test.py
	python3 -I scripts/parity_fixture_store_test.py
	python3 -I scripts/sleep_fixture_store_test.py
	python3 -I scripts/publish_scan_test.py
	python3 -I scripts/pre_push_test.py

goop-lint:
	python3 -I scripts/goop_lint.py

build:
	@mkdir -p .build
	CGO_ENABLED=1 GOTOOLCHAIN=local $(GO) build -trimpath -ldflags '$(LDFLAGS)' -o $(BIN) ./cmd/ghoops

smoke: build
	python3 scripts/smoke.py $(BIN)

install: check
	GO="$(GO)" SIGN_IDENTITY="$(SIGN_IDENTITY)" $(PYTHON) scripts/production_install.py --installed "$(INSTALLED)" --ldflags '$(LDFLAGS)'

keychain-check:
	"$(INSTALLED)" doctor --keychain-test --json

keychain-update-check:
	GO="$(GO)" SIGN_IDENTITY="$(SIGN_IDENTITY)" $(PYTHON) scripts/cross_build_keychain_check.py --installed "$(INSTALLED)"

live:
	"$(INSTALLED)" doctor --live --days 7 --json

clean:
	rm -rf .build

IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0
IOS_UI_TESTS ?= -only-testing:GHealthUITests
IOS_BUILD_NUMBER = $(shell date -u +%Y%m%d%H%M)
IOS_XCODE = xcodebuild -project ios/GHealth.xcodeproj -scheme GHealth -derivedDataPath ios/build/DerivedData

.PHONY: ios-project ios-simulator-project ios-core-test ios-build ios-test ios-screenshots

ios-project:
	$(PYTHON) -I ios/scripts/generate_device_project.py

ios-simulator-project:
	cd ios && xcodegen generate --spec project-simulator.yml

ios-core-test:
	cd ios/GHealthCore && swift test

ios-build: ios-simulator-project
	$(IOS_XCODE) -destination 'generic/platform=iOS Simulator' CURRENT_PROJECT_VERSION=$(IOS_BUILD_NUMBER) build

ios-test: ios-simulator-project ios-core-test
	$(IOS_XCODE) -destination '$(IOS_DESTINATION)' test

ios-screenshots: ios-simulator-project
	mkdir -p ios/build
	rm -rf ios/build/Screenshots.xcresult ios/build/screenshots
	$(IOS_XCODE) -destination '$(IOS_DESTINATION)' -resultBundlePath ios/build/Screenshots.xcresult test $(IOS_UI_TESTS)
	xcrun xcresulttool export attachments --path ios/build/Screenshots.xcresult --output-path ios/build/screenshots
	python3 ios/scripts/name_screenshots.py ios/build/screenshots

.PHONY: ios-bg-probe
ios-bg-probe: ios-simulator-project ios-core-test
	python3 ios/scripts/background_probe.py --destination '$(IOS_DESTINATION)'

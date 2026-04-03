IMAGE       ?= claude-devcon:latest
INSTALL_DIR ?= $(HOME)/.local/bin

.PHONY: all build test test-script test-image install uninstall clean

all: build test

build:
	docker build -t $(IMAGE) .

test: test-script test-image

test-script:
	@command -v bats >/dev/null 2>&1 \
	  || { echo "bats not found — install with: brew install bats-core"; exit 1; }
	bats tests/test_script.bats

test-image: build
	bash tests/test_image.sh

install:
	mkdir -p $(INSTALL_DIR)
	install -m 755 claude-devcon $(INSTALL_DIR)/claude-devcon
	@echo "Installed to $(INSTALL_DIR)/claude-devcon"
	@echo "Ensure $(INSTALL_DIR) is in your PATH"

uninstall:
	rm -f $(INSTALL_DIR)/claude-devcon
	@echo "Removed $(INSTALL_DIR)/claude-devcon"

clean:
	docker rmi $(IMAGE) 2>/dev/null || true

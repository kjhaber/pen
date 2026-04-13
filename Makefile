IMAGE_BASE   ?= pen-base:latest
IMAGE        ?= pen-claude:latest
IMAGE_CURSOR ?= pen-cursor:latest
INSTALL_DIR ?= $(HOME)/.local/bin
COMPLETION_BASH ?= $(HOME)/.local/share/bash-completion/completions
COMPLETION_ZSH  ?= $(HOME)/.zsh/completions

.PHONY: all build build-base build-claude build-cursor test test-script test-image install install-bin install-completions \
        uninstall uninstall-bin uninstall-completions clean

all: build test

build: build-claude build-cursor

build-base:
	docker build -t $(IMAGE_BASE) docker/base/

build-claude: build-base
	docker build -t $(IMAGE) docker/claude/

build-cursor:
	docker build -t $(IMAGE_CURSOR) docker/cursor/

test: test-script test-image

test-script:
	@command -v bats >/dev/null 2>&1 \
	  || { echo "bats not found — install with: brew install bats-core"; exit 1; }
	bats tests/test_script.bats

test-image: build
	PEN_IMAGE="$(IMAGE)" bash tests/test_image.sh
	PEN_IMAGE="$(IMAGE_CURSOR)" bash tests/test_image_cursor.sh

install: install-bin install-completions

install-bin:
	mkdir -p $(INSTALL_DIR)
	install -m 755 pen $(INSTALL_DIR)/pen
	@echo "Installed to $(INSTALL_DIR)/pen"
	@echo "Ensure $(INSTALL_DIR) is in your PATH"

install-completions:
	mkdir -p $(COMPLETION_BASH)
	install -m 644 completions/pen.bash $(COMPLETION_BASH)/pen
	mkdir -p $(COMPLETION_ZSH)
	install -m 644 completions/_pen $(COMPLETION_ZSH)/_pen
	@echo "Installed bash completion to $(COMPLETION_BASH)/pen"
	@echo "Installed zsh completion to $(COMPLETION_ZSH)/_pen"

uninstall: uninstall-bin uninstall-completions

uninstall-bin:
	rm -f $(INSTALL_DIR)/pen
	@echo "Removed $(INSTALL_DIR)/pen"

uninstall-completions:
	rm -f $(COMPLETION_BASH)/pen
	rm -f $(COMPLETION_ZSH)/_pen
	@echo "Removed completions"

clean:
	docker rmi $(IMAGE) $(IMAGE_CURSOR) $(IMAGE_BASE) 2>/dev/null || true

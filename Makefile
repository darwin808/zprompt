.PHONY: all build release install uninstall test clean

ZIG ?= zig
INSTALL_DIR ?= $(HOME)/.local/bin
NAME = zprompt

all: build

build:
	$(ZIG) build

release:
	$(ZIG) build -Doptimize=ReleaseFast

test:
	$(ZIG) build test

install: release
	@mkdir -p $(INSTALL_DIR)
	@cp zig-out/bin/$(NAME) $(INSTALL_DIR)/$(NAME)
	@chmod +x $(INSTALL_DIR)/$(NAME)
	@echo "Installed $(NAME) to $(INSTALL_DIR)/$(NAME)"
	@echo ""
	@echo "Add to your ~/.zshrc:"
	@echo '  eval "$$(zprompt init zsh)"'

uninstall:
	@rm -f $(INSTALL_DIR)/$(NAME)
	@echo "Removed $(INSTALL_DIR)/$(NAME)"

clean:
	rm -rf zig-out .zig-cache

# Development helpers
run:
	$(ZIG) build run

prompt:
	$(ZIG) build run -- prompt --status 0 --cmd-duration 0

init-zsh:
	$(ZIG) build run -- init zsh

# Cross compilation targets
build-linux-x86_64:
	$(ZIG) build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast

build-linux-aarch64:
	$(ZIG) build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast

build-macos-x86_64:
	$(ZIG) build -Dtarget=x86_64-macos -Doptimize=ReleaseFast

build-macos-aarch64:
	$(ZIG) build -Dtarget=aarch64-macos -Doptimize=ReleaseFast

# Build all platforms
build-all: build-linux-x86_64 build-linux-aarch64 build-macos-x86_64 build-macos-aarch64

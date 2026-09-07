SHELL = /bin/sh

ifeq ($(shell id -u), 0)
    PREFIX ?= /usr/local
else
    PREFIX ?= $(HOME)
endif

ifeq ($(PREFIX), $(HOME))
    FISH_FUNCTION_DIR ?= $(HOME)/.config/fish/functions
    FISH_COMPLETION_DIR ?= $(HOME)/.config/fish/completions
else
    FISH_FUNCTION_DIR ?= $(PREFIX)/share/fish/vendor_functions.d
    FISH_COMPLETION_DIR ?= $(PREFIX)/share/fish/vendor_completions.d
endif

all:

lint:
	shellcheck -s bash chtf/chtf.sh chtf/__chtf_terraform-install.sh etc/chtf-completion.bash test/*.sh
	fish --no-execute chtf/chtf.fish
	fish --no-execute etc/chtf-completion.fish

test:
	test/smoke.sh
	test/installer.sh
	test/detect.sh

install: install_sh install_fish

install_sh:
	install -d $(DESTDIR)$(PREFIX)/share/chtf
	install -m 0644 chtf/chtf.sh $(DESTDIR)$(PREFIX)/share/chtf
	install -m 0755 chtf/__chtf_terraform-install.sh $(DESTDIR)$(PREFIX)/share/chtf

install_fish:
	install -d $(DESTDIR)$(FISH_FUNCTION_DIR)
	install -m 0644 chtf/chtf.fish $(DESTDIR)$(FISH_FUNCTION_DIR)
	install -m 0755 chtf/__chtf_terraform-install.sh $(DESTDIR)$(FISH_FUNCTION_DIR)
	install -d $(DESTDIR)$(FISH_COMPLETION_DIR)
	install -m 0644 etc/chtf-completion.fish $(DESTDIR)$(FISH_COMPLETION_DIR)/chtf.fish

.PHONY: all lint test install

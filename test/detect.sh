#!/usr/bin/env bash
# Test install method detection and the homebrew method with fake uname and brew.
# shellcheck disable=SC2016 # scripts for child shells

set -eu -o pipefail

cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home" "$work/brew/Library/Taps/tmatilai/homebrew-terraforms" "$work/caskroom"
cat > "$work/bin/uname" <<'UNAME'
#!/bin/sh
echo "$FAKE_OS"
UNAME
cat > "$work/bin/brew" <<BREW
#!/bin/sh
case "\$1" in
    --repo) echo "$work/brew" ;;
    --caskroom) echo "$work/caskroom" ;;
    *) echo "brew \$*" ;;
esac
BREW
chmod +x "$work/bin/uname" "$work/bin/brew"

status=0
check() {
    if [[ "$2" == "$3" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        diff <(echo "$2") <(echo "$3") || true
        status=1
    fi
}

# run <shell> <os> <script>
run() {
    local cmd
    case "$1" in
        bash) cmd=(bash --norc -c "$3");;
        zsh) cmd=(zsh -f -c "$3");;
        fish) cmd=(fish --no-config -c "$3");;
    esac
    cmd[0]="$(command -v "${cmd[0]}")"
    env PATH="$work/bin:/usr/bin:/bin" HOME="$work/home" FAKE_OS="$2" "${cmd[@]}"
}

for shell in bash zsh fish; do
    case "$shell" in
        fish)
            detect='source chtf/chtf.fish; echo "$CHTF_AUTO_INSTALL_METHOD $CHTF_TERRAFORM_DIR"'
            install='set -g CHTF_AUTO_INSTALL yes; set -g CHTF_AUTO_INSTALL_METHOD homebrew
                source chtf/chtf.fish; chtf 1.5.7 2>&1; echo "exit=$status"'
            ;;
        *)
            detect='source chtf/chtf.sh; echo "$CHTF_AUTO_INSTALL_METHOD $CHTF_TERRAFORM_DIR"'
            install='CHTF_AUTO_INSTALL=yes; CHTF_AUTO_INSTALL_METHOD=homebrew
                source chtf/chtf.sh; chtf 1.5.7 2>&1; echo "exit=$?"'
            ;;
    esac

    check "$shell: tap detected on macOS" "homebrew $work/caskroom" "$(run "$shell" Darwin "$detect")"
    check "$shell: tap ignored on Linux" "zip $work/home/.terraforms" "$(run "$shell" Linux "$detect")"

    check "$shell: homebrew install on macOS" "chtf: Terraform version 1.5.7 not found
chtf: Installing Terraform version 1.5.7
brew trust tmatilai/terraforms
brew install --cask terraform-1-5-7
chtf: Failed to find terraform executable for 1.5.7
exit=1" "$(run "$shell" Darwin "$install")"

    check "$shell: homebrew install refused on Linux" "chtf: Terraform version 1.5.7 not found
chtf: Installing Terraform version 1.5.7
chtf: Homebrew Casks are supported only on macOS, use CHTF_AUTO_INSTALL_METHOD=zip
exit=1" "$(run "$shell" Linux "$install")"
done

exit $status

#!/usr/bin/env bash
# Test the zip installer against local fake releases, with a fake uname.

set -eu -o pipefail

cd "$(dirname "$0")/.."
installer="$PWD/chtf/__chtf_terraform-install.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sha256() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

# Fake release with a stub binary that prints its platform
make_release() {
    local version="$1"; shift
    local dir="$work/releases/terraform/$version"
    mkdir -p "$dir"
    for platform in "$@"; do
        printf '#!/bin/sh\necho "terraform %s %s"\n' "$version" "$platform" > "$work/terraform"
        chmod +x "$work/terraform"
        (cd "$work" && zip -q "$dir/terraform_${version}_${platform}.zip" terraform)
    done
    (cd "$dir" && sha256 ./*.zip | sed 's|\./||' > "terraform_${version}_SHA256SUMS")
}

make_release 1.5.7 darwin_amd64 darwin_arm64 linux_amd64 linux_arm64
make_release 0.15.5 darwin_amd64 linux_amd64
make_release 9.9.9 linux_amd64
printf '%064d  terraform_9.9.9_linux_amd64.zip\n' 0 > "$work/releases/terraform/9.9.9/terraform_9.9.9_SHA256SUMS"

# Fake uname
mkdir -p "$work/bin"
cat > "$work/bin/uname" <<'UNAME'
#!/bin/sh
case "$1" in
    -s) echo "$FAKE_OS" ;;
    -m) echo "$FAKE_ARCH" ;;
esac
UNAME
chmod +x "$work/bin/uname"

# install <os> <arch> <version> <install_dir>
install() {
    PATH="$work/bin:$PATH" FAKE_OS="$1" FAKE_ARCH="$2" CHTF_RELEASES_URL="file://$work/releases" \
        "$installer" "$3" "$4" 2>/dev/null
}

installed() {
    if [[ -x "$1/terraform" ]]; then "$1/terraform"; else echo none; fi
}

status=0
check() {
    if [[ "$2" == "$3" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        echo "  expected: $2"
        echo "  actual:   $3"
        status=1
    fi
}

install Darwin arm64 1.5.7 "$work/darwin-arm64"
check "darwin arm64" "terraform 1.5.7 darwin_arm64" "$(installed "$work/darwin-arm64")"

install Darwin x86_64 1.5.7 "$work/darwin-amd64"
check "darwin amd64" "terraform 1.5.7 darwin_amd64" "$(installed "$work/darwin-amd64")"

install Linux aarch64 1.5.7 "$work/linux-arm64"
check "linux arm64" "terraform 1.5.7 linux_arm64" "$(installed "$work/linux-arm64")"

install Linux x86_64 1.5.7 "$work/linux-amd64"
check "linux amd64" "terraform 1.5.7 linux_amd64" "$(installed "$work/linux-amd64")"

install Darwin arm64 0.15.5 "$work/rosetta"
check "darwin arm64 falls back to amd64" "terraform 0.15.5 darwin_amd64" "$(installed "$work/rosetta")"

install Linux aarch64 0.15.5 "$work/no-build" && rc=0 || rc=$?
check "missing build fails" 1 "$rc"
check "missing build installs nothing" none "$(installed "$work/no-build")"

install Linux x86_64 9.9.9 "$work/bad-sum" && rc=0 || rc=$?
check "checksum mismatch fails" 1 "$rc"
check "checksum mismatch installs nothing" none "$(installed "$work/bad-sum")"

install Linux x86_64 1.2.3 "$work/no-version" && rc=0 || rc=$?
check "unknown version fails" 1 "$rc"

# End to end through chtf in bash and fish, with config set like in the README
e2e_env=(PATH="$work/bin:/usr/bin:/bin" FAKE_OS=Linux FAKE_ARCH=x86_64)
expected="terraform 1.5.7 linux_amd64
 * 1.5.7"

actual="$(env "${e2e_env[@]}" "$(command -v bash)" --norc -c "
    CHTF_RELEASES_URL='file://$work/releases'
    CHTF_AUTO_INSTALL=yes
    CHTF_AUTO_INSTALL_METHOD=zip
    CHTF_TERRAFORM_DIR='$work/tf-bash'
    source chtf/chtf.sh
    chtf 1.5.7 >/dev/null 2>&1; terraform; chtf")"
check "chtf.sh installs and switches" "$expected" "$actual"

actual="$(env "${e2e_env[@]}" "$(command -v fish)" --no-config -c "
    set -g CHTF_RELEASES_URL 'file://$work/releases'
    set -g CHTF_AUTO_INSTALL yes
    set -g CHTF_AUTO_INSTALL_METHOD zip
    set -g CHTF_TERRAFORM_DIR '$work/tf-fish'
    source chtf/chtf.fish
    chtf 1.5.7 >/dev/null 2>&1; terraform; chtf")"
check "chtf.fish installs and switches" "$expected" "$actual"

exit $status

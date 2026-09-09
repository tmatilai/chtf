#!/usr/bin/env bash
# Test the zip installer against local fake releases, with a fake uname and a
# throwaway signing key.

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

# Throwaway signing key in its own gpg home. The tests need gpg, like CI has.
if ! command -v gpg >/dev/null; then
    echo "installer.sh: gpg is required for the signature tests" >&2
    exit 1
fi
gnupg="$work/gnupg"
mkdir -m 700 "$gnupg"
trap 'gpgconf --homedir "$gnupg" --kill gpg-agent; rm -rf "$work"' EXIT
gpg_batch=(gpg --batch --quiet --homedir "$gnupg" --pinentry-mode loopback --passphrase '')
"${gpg_batch[@]}" --quick-generate-key 'chtf test' ed25519 sign 0
"${gpg_batch[@]}" --armor --export 'chtf test' > "$work/key.asc"

sign_release() { # <version>
    local dir="$work/releases/terraform/$1"
    rm -f "$dir/terraform_$1_SHA256SUMS.sig"
    "${gpg_batch[@]}" --detach-sign -o "$dir/terraform_$1_SHA256SUMS.sig" "$dir/terraform_$1_SHA256SUMS"
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
    sign_release "$version"
}

make_release 1.5.7 darwin_amd64 darwin_arm64 linux_amd64 linux_arm64
make_release 0.15.5 darwin_amd64 linux_amd64
make_release 9.9.9 linux_amd64
printf '%064d  terraform_9.9.9_linux_amd64.zip\n' 0 > "$work/releases/terraform/9.9.9/terraform_9.9.9_SHA256SUMS"
sign_release 9.9.9
# Checksums tampered after signing, and not signed at all
make_release 8.8.8 linux_amd64
printf '%064d  terraform_8.8.8_linux_amd64.zip\n' 0 > "$work/releases/terraform/8.8.8/terraform_8.8.8_SHA256SUMS"
make_release 7.7.7 linux_amd64
rm "$work/releases/terraform/7.7.7/terraform_7.7.7_SHA256SUMS.sig"

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
# The e2e cases below restrict PATH to system dirs, keep gpg reachable
ln -s "$(command -v gpg)" "$work/bin/gpg"

# install <os> <arch> <version> <install_dir>
install() {
    PATH="$work/bin:$PATH" FAKE_OS="$1" FAKE_ARCH="$2" CHTF_RELEASES_URL="file://$work/releases" \
        CHTF_GPG_KEY="$work/key.asc" "$installer" "$3" "$4" 2>/dev/null
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

install Linux x86_64 8.8.8 "$work/bad-sig" && rc=0 || rc=$?
check "bad signature fails" 1 "$rc"
check "bad signature installs nothing" none "$(installed "$work/bad-sig")"

install Linux x86_64 7.7.7 "$work/no-sig" && rc=0 || rc=$?
check "missing signature fails" 1 "$rc"

CHTF_VERIFY_SIGNATURE=no install Linux x86_64 7.7.7 "$work/skip-sig"
check "CHTF_VERIFY_SIGNATURE=no skips the signature" "terraform 7.7.7 linux_amd64" "$(installed "$work/skip-sig")"

install Linux x86_64 1.2.3 "$work/no-version" && rc=0 || rc=$?
check "unknown version fails" 1 "$rc"

# The install helper hides stderr, so run the installer directly for messages
actual="$(PATH="$work/bin:$PATH" FAKE_OS=Linux FAKE_ARCH=x86_64 "$installer" ../x "$work/bad-version" 2>&1)" && rc=0 || rc=$?
check "invalid version fails" "1 chtf: Invalid version: ../x" "$rc $actual"

actual="$(PATH="$work/bin:$PATH" FAKE_OS=Linux FAKE_ARCH=x86_64 CHTF_RELEASES_URL="file://$work/releases" \
    CHTF_GPG_KEY="$work/key.asc" "$installer" 8.8.8 "$work/bad-sig-msg" 2>&1 | tail -n 1)" && rc=0 || rc=$?
check "bad signature message" "1 chtf: Signature verification failed for SHA256SUMS" "$rc $actual"

# Everything the installer needs except gpg
mkdir "$work/no-gpg"
for tool in bash unzip curl sha256sum shasum awk cut tr mktemp mkdir mv rm cat; do
    if command -v "$tool" >/dev/null; then
        ln -s "$(command -v "$tool")" "$work/no-gpg/$tool"
    fi
done
ln -s "$work/bin/uname" "$work/no-gpg/uname"
no_gpg_env=(PATH="$work/no-gpg" FAKE_OS=Linux FAKE_ARCH=x86_64 CHTF_RELEASES_URL="file://$work/releases")
actual="$(env "${no_gpg_env[@]}" "$installer" 1.5.7 "$work/no-gpg-auto" 2>&1)" && rc=0 || rc=$?
check "missing gpg skips the signature with a notice" "0 chtf: gpg not found, skipping the signature verification" "$rc $actual"
check "missing gpg still installs" "terraform 1.5.7 linux_amd64" "$(installed "$work/no-gpg-auto")"
actual="$(env "${no_gpg_env[@]}" CHTF_VERIFY_SIGNATURE=yes "$installer" 1.5.7 "$work/no-gpg-yes" 2>&1)" && rc=0 || rc=$?
check "CHTF_VERIFY_SIGNATURE=yes requires gpg" "1 chtf: Required tool not found: gpg" "$rc $actual"

# Only bash and the fake uname on PATH, so unzip is missing
mkdir "$work/bash-only" && ln -s "$(command -v bash)" "$work/bash-only/bash"
actual="$(PATH="$work/bin:$work/bash-only" FAKE_OS=Linux FAKE_ARCH=x86_64 "$installer" 1.5.7 "$work/no-unzip" 2>&1)" && rc=0 || rc=$?
check "missing tool fails early" "1 chtf: Required tool not found: unzip" "$rc $actual"

# Alternative tools are listed with a '/' (the IFS join in require). The other
# direct cases run under the shebang bash only, so use /bin/bash here as well
bashes=("$(command -v bash)")
if [[ -x /bin/bash ]] && [[ "$(/bin/bash --version)" != "$(bash --version)" ]]; then
    bashes+=(/bin/bash)
fi
mkdir "$work/no-net" && ln -s "$(command -v unzip)" "$work/no-net/unzip"
for bash_bin in "${bashes[@]}"; do
    ln -sf "$bash_bin" "$work/no-net/bash"
    actual="$(PATH="$work/bin:$work/no-net" FAKE_OS=Linux FAKE_ARCH=x86_64 "$installer" 1.5.7 "$work/no-curl" 2>&1)" && rc=0 || rc=$?
    check "missing download tool ($bash_bin)" "1 chtf: Required tool not found: curl/wget" "$rc $actual"
done

# End to end through chtf in bash and fish, with config set like in the README
e2e_env=(PATH="$work/bin:/usr/bin:/bin" FAKE_OS=Linux FAKE_ARCH=x86_64)
expected="terraform 1.5.7 linux_amd64
 * 1.5.7"

actual="$(env "${e2e_env[@]}" "$(command -v bash)" --norc -c "
    CHTF_RELEASES_URL='file://$work/releases'
    CHTF_GPG_KEY='$work/key.asc'
    CHTF_AUTO_INSTALL=yes
    CHTF_AUTO_INSTALL_METHOD=zip
    CHTF_TERRAFORM_DIR='$work/tf-bash'
    source chtf/chtf.sh
    chtf 1.5.7 >/dev/null 2>&1; terraform; chtf")"
check "chtf.sh installs and switches" "$expected" "$actual"

actual="$(env "${e2e_env[@]}" "$(command -v fish)" --no-config -c "
    set -g CHTF_RELEASES_URL 'file://$work/releases'
    set -g CHTF_GPG_KEY '$work/key.asc'
    set -g CHTF_AUTO_INSTALL yes
    set -g CHTF_AUTO_INSTALL_METHOD zip
    set -g CHTF_TERRAFORM_DIR '$work/tf-fish'
    source chtf/chtf.fish
    chtf 1.5.7 >/dev/null 2>&1; terraform; chtf")"
check "chtf.fish installs and switches" "$expected" "$actual"

exit $status

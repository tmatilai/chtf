#!/usr/bin/env bash
# Download a Terraform release, verify its checksum and signature, and install the binary.
#
# Usage: __chtf_terraform-install.sh <version> <install_dir>
#
# The checksum file is verified against HashiCorp's PGP signature when gpg is
# available. CHTF_VERIFY_SIGNATURE=yes requires gpg, =no skips the check.
# CHTF_GPG_KEY names an ASCII-armored public key to use instead of the embedded
# HashiCorp key, for a mirror that signs its own checksum files.

set -eu -o pipefail

usage="usage: ${0##*/} <version> <install_dir>"
version="${1:?$usage}"
install_dir="${2:?$usage}"
release_url="${CHTF_RELEASES_URL:-https://releases.hashicorp.com}/terraform/$version"

if [[ ! "$version" =~ ^[0-9][0-9A-Za-z.-]*$ ]]; then
    echo "chtf: Invalid version: $version" >&2
    exit 1
fi

# Succeeds if any of the given tools is available
require() {
    for tool in "$@"; do
        command -v "$tool" >/dev/null && return 0
    done
    local IFS=/
    echo "chtf: Required tool not found: $*" >&2
    exit 1
}
require unzip
require curl wget
require sha256sum shasum

case "${CHTF_VERIFY_SIGNATURE:-auto}" in
    yes|true|1)
        require gpg
        verify=yes
        ;;
    no|false|0)
        verify=no
        ;;
    *)
        if command -v gpg >/dev/null; then
            verify=yes
        else
            echo 'chtf: gpg not found, skipping the signature verification' >&2
            verify=no
        fi
        ;;
esac

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    armv*) arch=arm ;;
    i?86) arch=386 ;;
    *) echo "chtf: Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Never follow redirects to plain HTTP; show progress only on a terminal
curl_opts=(-fL --proto-redir '-all,https' --connect-timeout 30 --retry 3)
if [[ -t 2 ]]; then
    curl_opts+=(-#)
else
    curl_opts+=(-sS)
fi
# wget can only refuse plain HTTP altogether, redirects included
wget_opts=(-q)
if [[ "$release_url" == https://* ]]; then
    wget_opts+=(--https-only)
fi

download() {
    if command -v curl >/dev/null; then
        curl "${curl_opts[@]}" -o "$2" "$1"
    else
        wget "${wget_opts[@]}" -O "$2" "$1"
    fi || { echo "chtf: Failed to download $1" >&2; exit 1; }
}

sha256() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi | cut -d ' ' -f 1
}

checksum_for() {
    awk -v file="$1" '$2 == file { print $1 }' "$tmp_dir/SHA256SUMS"
}

# HashiCorp's release signing key, fingerprint
# C874 011F 0AB4 0511 0D02 1055 3436 5D94 72D7 468F, expires 2030-02-26.
# A minimal export of https://www.hashicorp.com/.well-known/pgp-key.txt with
# only the signing subkey (374E C75B 4859 1360 4A83 1CC7 C820 C6D5 CD27 AB87).
hashicorp_key() {
    cat <<'KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
=bov7
-----END PGP PUBLIC KEY BLOCK-----
KEY
}

# Verify a detached signature in an isolated gpg home with a keyring built
# from the key file alone, so the user's keyring, options and gpg-agent are
# never involved
verify_signature() { # <signature> <file>
    local gnupg="$tmp_dir/gnupg" key_file="$tmp_dir/key.asc"
    if [[ -n "${CHTF_GPG_KEY:-}" ]]; then
        key_file="$CHTF_GPG_KEY"
    else
        hashicorp_key > "$key_file"
    fi
    mkdir -m 700 "$gnupg"
    gpg --batch --quiet --homedir "$gnupg" --dearmor -o "$gnupg/keyring.gpg" "$key_file" ||
        { echo "chtf: Failed to read the signing key $key_file" >&2; exit 1; }
    if ! gpg --batch --quiet --no-autostart --homedir "$gnupg" \
            --no-default-keyring --keyring "$gnupg/keyring.gpg" \
            --trust-model always --verify "$1" "$2" 2> "$gnupg/verify.log"; then
        cat "$gnupg/verify.log" >&2
        echo "chtf: Signature verification failed for ${2##*/}" >&2
        exit 1
    fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sums_file="terraform_${version}_SHA256SUMS"
download "$release_url/$sums_file" "$tmp_dir/SHA256SUMS"

if [[ "$verify" == yes ]]; then
    if [[ -n "${CHTF_GPG_KEY:-}" ]]; then
        sig_file="$sums_file.sig"
    else
        # The plain .sig of releases before April 2021 was made with a key
        # HashiCorp has since revoked. This one is signed with the current
        # key for every release.
        sig_file="$sums_file.72D7468F.sig"
    fi
    download "$release_url/$sig_file" "$tmp_dir/SHA256SUMS.sig"
    verify_signature "$tmp_dir/SHA256SUMS.sig" "$tmp_dir/SHA256SUMS"
fi

zip_file="terraform_${version}_${os}_${arch}.zip"
expected="$(checksum_for "$zip_file")"
# Versions before 1.0.2 have no darwin_arm64 build; run amd64 under Rosetta
if [[ -z "$expected" && "$os/$arch" == darwin/arm64 ]]; then
    zip_file="terraform_${version}_darwin_amd64.zip"
    expected="$(checksum_for "$zip_file")"
fi
if [[ -z "$expected" ]]; then
    echo "chtf: No Terraform $version build for ${os}_${arch}" >&2
    exit 1
fi

download "$release_url/$zip_file" "$tmp_dir/$zip_file"
if [[ "$(sha256 "$tmp_dir/$zip_file")" != "$expected" ]]; then
    echo "chtf: Checksum mismatch for $zip_file" >&2
    exit 1
fi

unzip -q "$tmp_dir/$zip_file" terraform -d "$tmp_dir"
mkdir -p "$install_dir"
mv "$tmp_dir/terraform" "$install_dir/"

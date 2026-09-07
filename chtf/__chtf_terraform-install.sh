#!/usr/bin/env bash
# Download a Terraform release, verify its checksum, and install the binary.
#
# Usage: __chtf_terraform-install.sh <version> <install_dir>

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

download() {
    if command -v curl >/dev/null; then
        curl "${curl_opts[@]}" -o "$2" "$1"
    else
        wget -q -O "$2" "$1"
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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

download "$release_url/terraform_${version}_SHA256SUMS" "$tmp_dir/SHA256SUMS"

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

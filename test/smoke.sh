#!/usr/bin/env bash
# Smoke test listing and switching in bash, zsh, and fish against a fixture dir.

set -eu -o pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Glob characters in the dir name must be treated literally
fixture="$tmp/tf*[1]"

# Zip layout, Cask layout, and a prerelease Cask
mkdir -p "$fixture/terraform-1.5.7" "$fixture/terraform-1-9-0/1.9.0" \
    "$fixture/terraform-0-10-0-rc1/0.10.0-rc1"
touch "$fixture/terraform-1.5.7/terraform" "$fixture/terraform-1-9-0/1.9.0/terraform" \
    "$fixture/terraform-0-10-0-rc1/0.10.0-rc1/terraform"
chmod +x "$fixture/terraform-1.5.7/terraform" "$fixture/terraform-1-9-0/1.9.0/terraform" \
    "$fixture/terraform-0-10-0-rc1/0.10.0-rc1/terraform"

path='/usr/bin:/bin'
expected="   0.10.0-rc1
   1.5.7
   1.9.0
$fixture/terraform-1-9-0/1.9.0:$path
$fixture/terraform-0-10-0-rc1/0.10.0-rc1:$path
$fixture/terraform-1.5.7:$path
   0.10.0-rc1
 * 1.5.7
   1.9.0
$path
exit=1
chtf: Invalid version: ../x
exit=1
chtf: Terraform version 9.9.9 not found
chtf: Not a terminal, set CHTF_AUTO_INSTALL=yes to install automatically
chtf: Installing Terraform version 9.9.9"

sh_script="
CHTF_AUTO_INSTALL=no
CHTF_TERRAFORM_DIR='$fixture'
source chtf/chtf.sh
chtf
chtf 1.9.0; echo \"\$PATH\"
chtf 0.10.0-rc1; echo \"\$PATH\"
chtf 1.5.7; echo \"\$PATH\"
chtf
chtf system; echo \"\$PATH\"
chtf 9.9.9 2>/dev/null; echo \"exit=\$?\"
chtf ../x 2>&1; echo \"exit=\$?\"
CHTF_RELEASES_URL=file:///nonexistent
CHTF_AUTO_INSTALL=nope; chtf 9.9.9 </dev/null 2>&1
CHTF_AUTO_INSTALL=true; chtf 9.9.9 2>&1 | grep Installing || echo 'no install'
"

fish_script="
set -gx CHTF_AUTO_INSTALL no
set -gx CHTF_TERRAFORM_DIR '$fixture'
source chtf/chtf.fish
chtf
chtf 1.9.0; string join : \$PATH
chtf 0.10.0-rc1; string join : \$PATH
chtf 1.5.7; string join : \$PATH
chtf
chtf system; string join : \$PATH
chtf 9.9.9 2>/dev/null; echo \"exit=\$status\"
chtf ../x 2>&1; echo \"exit=\$status\"
set -gx CHTF_RELEASES_URL file:///nonexistent
set -gx CHTF_AUTO_INSTALL nope; chtf 9.9.9 </dev/null 2>&1
set -gx CHTF_AUTO_INSTALL true; chtf 9.9.9 2>&1 | grep Installing; or echo 'no install'
"

# Sourcing and running must also work with 'set -u' in the user's rc
setu_script="set -u
$sh_script"

status=0
for shell in bash zsh fish; do
    # Skip user rc files, they may alter PATH
    case "$shell" in
        bash) cmd=(bash --norc -c "$sh_script");;
        zsh) cmd=(zsh -f -c "$sh_script");;
        fish) cmd=(fish --no-config -c "$fish_script");;
    esac
    cmd[0]="$(command -v "${cmd[0]}")"
    actual="$(env PATH="$path" "${cmd[@]}")"
    if [[ "$actual" == "$expected" ]]; then
        echo "$shell: OK"
    else
        echo "$shell: FAIL"
        diff <(echo "$expected") <(echo "$actual") || true
        status=1
    fi
done

for shell in bash zsh; do
    case "$shell" in
        bash) cmd=(bash --norc -c "$setu_script");;
        zsh) cmd=(zsh -f -c "$setu_script");;
    esac
    cmd[0]="$(command -v "${cmd[0]}")"
    actual="$(env PATH="$path" "${cmd[@]}")"
    if [[ "$actual" == "$expected" ]]; then
        echo "$shell (set -u): OK"
    else
        echo "$shell (set -u): FAIL"
        diff <(echo "$expected") <(echo "$actual") || true
        status=1
    fi
done
exit $status

#!/usr/bin/env bash
# Smoke test listing and switching in bash, zsh, and fish against a fixture dir.

set -eu -o pipefail

cd "$(dirname "$0")/.."

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

# Zip layout and Cask layout
mkdir -p "$fixture/terraform-1.5.7" "$fixture/terraform-1-9-0/1.9.0"
touch "$fixture/terraform-1.5.7/terraform" "$fixture/terraform-1-9-0/1.9.0/terraform"
chmod +x "$fixture/terraform-1.5.7/terraform" "$fixture/terraform-1-9-0/1.9.0/terraform"

path='/usr/bin:/bin'
expected="   1.5.7
   1.9.0
$fixture/terraform-1-9-0/1.9.0:$path
$fixture/terraform-1.5.7:$path
 * 1.5.7
   1.9.0
$path
exit=1"

sh_script="
CHTF_AUTO_INSTALL=no
CHTF_TERRAFORM_DIR='$fixture'
source chtf/chtf.sh
chtf
chtf 1.9.0; echo \"\$PATH\"
chtf 1.5.7; echo \"\$PATH\"
chtf
chtf system; echo \"\$PATH\"
chtf 9.9.9 2>/dev/null; echo \"exit=\$?\"
"

fish_script="
set -gx CHTF_AUTO_INSTALL no
set -gx CHTF_TERRAFORM_DIR '$fixture'
source chtf/chtf.fish
chtf
chtf 1.9.0; string join : \$PATH
chtf 1.5.7; string join : \$PATH
chtf
chtf system; string join : \$PATH
chtf 9.9.9 2>/dev/null; echo \"exit=\$status\"
"

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
exit $status

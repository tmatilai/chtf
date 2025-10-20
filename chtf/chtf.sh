# Copyright (c) 2012-2016 Hal Brodigan
# Copyright (c) 2016-2018 Yleisradio Oy
# Copyright (c) 2020, 2024-2025 Teemu Matilainen
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

CHTF_VERSION='2.3.1-dev'

# Set defaults

: "${CHTF_AUTO_INSTALL:=ask}"

if [[ -z "$CHTF_TERRAFORM_DIR" ]]; then
    if [[ "$CHTF_AUTO_INSTALL_METHOD" == 'homebrew' ]]; then
        CHTF_TERRAFORM_DIR="$(brew --caskroom)"
    elif [[ -z "$CHTF_AUTO_INSTALL_METHOD" ]] &&
        command -v brew >/dev/null &&
        [[ -d "$(brew --repo)/Library/Taps/tmatilai/homebrew-terraforms" || -d "$(brew --repo)/Library/Taps/yleisradio/homebrew-terraforms" ]]; then
        # https://github.com/tmatilai/homebrew-terraforms in use
        CHTF_TERRAFORM_DIR="$(brew --caskroom)"
        CHTF_AUTO_INSTALL_METHOD='homebrew'
    else
        CHTF_TERRAFORM_DIR="$HOME/.terraforms"
    fi
fi

: "${CHTF_AUTO_INSTALL_METHOD:=zip}"

chtf() {
    case "$1" in
        -h|--help)
            echo "usage: chtf [<version> | system]"
            ;;
        -V|--version)
            echo "chtf: $CHTF_VERSION"
            ;;
        "")
            _chtf_list
            ;;
        system)
            _chtf_reset
            ;;
        *)
            _chtf_use "$1"
            ;;
    esac
}

_chtf_cask_version() {
    tr '.' '-' <<< "$1"
}

_chtf_version() {
    tr '-' '.' <<< "$1"
}

_chtf_reset() {
    [[ -z "$CHTF_CURRENT" ]] && return 0

    PATH=":$PATH:"; PATH="${PATH//:$CHTF_CURRENT:/:}"
    PATH="${PATH#:}"; PATH="${PATH%:}"
    hash -r

    unset CHTF_CURRENT
    unset CHTF_CURRENT_TERRAFORM_VERSION
}

_chtf_use() {
    local tf_version="$1"

    if ! _chtf_find_executable "$tf_version" > /dev/null; then
        _chtf_install "$tf_version" || return 1
    fi

    local tf_path
    if ! tf_path="$(_chtf_find_executable "$tf_version")"; then
        echo "chtf: Failed to find terraform executable for $tf_version" >&2
        return 1
    fi

    _chtf_reset

    export CHTF_CURRENT="$tf_path"
    export CHTF_CURRENT_TERRAFORM_VERSION="$tf_version"
    export PATH="$CHTF_CURRENT:$PATH"
}

_chtf_list() (
    # Avoid glob matching errors.
    # Note that we do this in a subshell to restrict the scope.
    # bash
    shopt -s nullglob 2>/dev/null || true
    # zsh
    setopt null_glob 2>/dev/null || true

    for tf_path in "$CHTF_TERRAFORM_DIR"/terraform-*; do
        local tf_cask_version="${tf_path##*/terraform-}"
        local tf_version="$(_chtf_version "$tf_cask_version")"

        if [[ -x "$tf_path/$tf_version/terraform" ]] || [[ -x "$tf_path/terraform.exe" ]]; then
            echo "$tf_version"
        fi
    done | sort --version-sort --unique | while read -r tf_version; do
        printf '%s %s\n' "$(_chtf_list_prefix "$tf_version")" "$tf_version"
    done;
)

_chtf_list_prefix() {
    local tf_version="$1"
    if [[ "$tf_version" == "$CHTF_CURRENT_TERRAFORM_VERSION" ]]; then
        printf ' *'
    else
        printf '  '
    fi
}

_chtf_find_executable() {
    local tf_version="$1"
    local tf_cask_version="$(_chtf_cask_version "$tf_version")"

    local tf_paths=(
        # New Cask path
        "$CHTF_TERRAFORM_DIR/terraform-$tf_cask_version/$tf_version"
        # Old Cask path
        "$CHTF_TERRAFORM_DIR/terraform-$tf_version/$tf_version"
        # Zip path
        "$CHTF_TERRAFORM_DIR/terraform-$tf_version"
    )

    for tf_path in "${tf_paths[@]}"; do
        if [[ -x "$tf_path/terraform" ]]; then
            echo "$tf_path"
            return
        fi
    done

    return 1
}

_chtf_install() {
    local tf_version="$1"
    echo "chtf: Terraform version $tf_version not found" >&2

    local install_function="_chtf_install_$CHTF_AUTO_INSTALL_METHOD"
    if ! command -v "$install_function" >/dev/null; then
        echo "chtf: Unknown install method: $CHTF_AUTO_INSTALL_METHOD" >&2
        return 1
    fi

    _chtf_confirm "$tf_version" || return 1

    echo "chtf: Installing Terraform version $tf_version"
    $install_function "$tf_version"
}

_chtf_install_homebrew() {
    local tf_cask_version="$(_chtf_cask_version "$1")"
    brew install --cask "terraform-$tf_cask_version"
}

_chtf_install_zip() {
    local tf_version="$1"
    local tf_dir="$CHTF_TERRAFORM_DIR/terraform-$tf_version"

    mkdir -p "$tf_dir"
    env TF_INSTALL_DIR="$tf_dir" "$(_chtf_root_dir)"/__chtf_terraform-install.sh -i "$tf_version"
}

_chtf_confirm() {
    case "$CHTF_AUTO_INSTALL" in
        no|false|0)
            return 1;;
        ask)
            printf 'chtf: Do you want to install it? [yN] '
            if [[ -n "$ZSH_NAME" ]]; then
                # shellcheck disable=SC2162 # ignore zsh command
                read -k reply
            else
                read -n 1 -r reply
            fi
            echo
            [[ "$reply" == [Yy] ]] || return 1
            ;;
    esac
}

_chtf_root_dir() {
    if [[ -n "$BASH" ]]; then
        dirname "${BASH_SOURCE[0]}"
    elif [[ -n "$ZSH_NAME" ]]; then
        dirname "${(%):-%x}"
    else
        echo 'chtf: [WARN] Unknown shell' >&2
    fi
}

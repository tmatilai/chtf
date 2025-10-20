# Copyright (c) 2017 Alex Kulbii
# Copyright (c) 2018 Yleisradio Oy
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

set -g CHTF_VERSION 2.3.1-dev

# Set defaults

set -q CHTF_AUTO_INSTALL; or set -g CHTF_AUTO_INSTALL ask

if not set -q CHTF_TERRAFORM_DIR
    if test "$CHTF_AUTO_INSTALL_METHOD" = homebrew
        set -g CHTF_TERRAFORM_DIR (brew --caskroom)
    else if test -z "$CHTF_AUTO_INSTALL_METHOD"
        and type -q brew
        and begin
            test -d (brew --repo)/Library/Taps/tmatilai/homebrew-terraforms
            or test -d (brew --repo)/Library/Taps/yleisradio/homebrew-terraforms
        end
        # https://github.com/tmatilai/homebrew-terraforms in use
        set -g CHTF_TERRAFORM_DIR (brew --caskroom)
        set -g CHTF_AUTO_INSTALL_METHOD homebrew
    else
        set -g CHTF_TERRAFORM_DIR $HOME/.terraforms
    end
end

set -q CHTF_AUTO_INSTALL_METHOD; or set -g CHTF_AUTO_INSTALL_METHOD zip

function chtf
    switch $argv[1]
        case -h --help
            echo 'usage: chtf [<version> | system]'
        case -V --version
            echo "chtf: $CHTF_VERSION"
        case ''
            _chtf_list
        case system
            _chtf_reset
        case '*'
            _chtf_use $argv[1]
    end
end

function _chtf_cask_version -a tf_version
    string replace -a '.' '-' -- $tf_version
end

function _chtf_version -a tf_cask_version
    string replace -a '-' '.' -- $tf_cask_version
end

function _chtf_reset
    test -z "$CHTF_CURRENT"; and return 0

    set PATH (string match -v -- $CHTF_CURRENT $PATH)

    set -e CHTF_CURRENT
    set -e CHTF_CURRENT_TERRAFORM_VERSION
end

function _chtf_use -a tf_version
    set -l tf_cask_version (_chtf_cask_version $tf_version)

    if not _chtf_find_executable $tf_version > /dev/null
        _chtf_install $tf_version; or return 1
    end

    set -l tf_path (_chtf_find_executable $tf_version)
    if test -z $tf_path
        echo "chtf: Failed to find terraform executable for $tf_version" >&2
        return 1
    end

    _chtf_reset

    set -gx CHTF_CURRENT $tf_path
    set -gx CHTF_CURRENT_TERRAFORM_VERSION $tf_version
    set PATH $CHTF_CURRENT $PATH
end

function _chtf_list
    for tf_path in $CHTF_TERRAFORM_DIR/terraform-*
        set -l tf_cask_version (string replace -r '.*/terraform-' '' $tf_path)
        set -l tf_version (_chtf_version $tf_cask_version)

        if test -x $tf_path/$tf_version/terraform -o -x $tf_path/terraform
            echo $tf_version
        end
    end | sort --version-sort --unique | while read -l tf_version
        printf '%s %s\n' (_chtf_list_prefix $tf_version) $tf_version
    end
end

function _chtf_list_prefix -a tf_version
    if test $tf_version = "$CHTF_CURRENT_TERRAFORM_VERSION"
        printf ' *'
    else
        printf '  '
    end
end

function _chtf_find_executable -a tf_version
    set -l tf_cask_version (_chtf_cask_version $tf_version)

    set -l tf_paths \
        # New Cask path
        $CHTF_TERRAFORM_DIR/terraform-$tf_cask_version/$tf_version \
        # Old Cask path
        $CHTF_TERRAFORM_DIR/terraform-$tf_version/$tf_version \
        # Zip path
        $CHTF_TERRAFORM_DIR/terraform-$tf_version

    for tf_path in $tf_paths
        if test -x $tf_path/terraform
            echo $tf_path
            return
        end
    end

    return 1
end

function _chtf_install -a tf_version
    echo "chtf: Terraform version $tf_version not found" >&2

    set -l install_function "_chtf_install_$CHTF_AUTO_INSTALL_METHOD"
    if not type -q $install_function
        echo "chtf: Unknown install method: $CHTF_AUTO_INSTALL_METHOD" >&2
        return 1
    end

    _chtf_confirm $tf_version; or return 1

    echo "chtf: Installing Terraform version $tf_version"
    $install_function $tf_version
end

function _chtf_install_homebrew -a tf_version
    set -l tf_cask_version (_chtf_cask_version $tf_version)
    brew install --cask "terraform-$tf_cask_version"
end

function _chtf_install_zip -a tf_version
    set -l tf_dir $CHTF_TERRAFORM_DIR/terraform-$tf_version
    set -l installer (_chtf_root_dir)/__chtf_terraform-install.sh

    mkdir -p $tf_dir
    env TF_INSTALL_DIR=$tf_dir $installer -i $tf_version
end

function _chtf_confirm
    switch "$CHTF_AUTO_INSTALL"
        case no false 0
            return 1
        case ask
            read -n 1 -P 'chtf: Do you want to install it? [yN] ' reply
            string match -qr '[Yy]' $reply; or return 1
    end
end

function _chtf_root_dir
    dirname (status --current-filename)
end

# chtf - Terraform version switcher

Do you need different Terraform versions on different projects? Or maybe you want to test your modules with a new Terraform version?

`chtf` is a small shell tool for selecting a specified [Terraform](https://www.terraform.io/) version. It can also install the specified version automatically.

---

## Requirements

`chtf` supports currently [bash](http://www.gnu.org/software/bash/), [zsh](http://zsh.sourceforge.net/), and [fish](https://fishshell.com/) shells. Version switching itself doesn't have any external dependencies.

Optional automatic install of missing Terraform versions requires either:

- [Homebrew](https://brew.sh/) with [tmatilai/terraforms](https://github.com/tmatilai/homebrew-terraforms) Tap (see below)
- bash, unzip, and wget or curl

---

## Installation

### Homebrew

On MacOS (and OSX) the easiest way is to use Homebrew. After installing Homebrew, run:

    brew install tmatilai/terraforms/chtf

Homebrew also installs the completion for all supported shells.

### All systems

Manual installation on all systems:

    curl -L -o chtf-2.3.0.tar.gz https://github.com/tmatilai/chtf/archive/v2.3.0.tar.gz
    tar -xzvf chtf-2.3.0.tar.gz
    cd chtf-2.3.0/
    make install

The default installation location is `$HOME/share/chtf/` for bash/zsh, and `$HOME/.config/fish/` for fish. See the [Tips section](#tips) for installing to other locations.

The `etc/` directory includes completion files for the supported shells. Follow your shell's instructions how to install them. The fish autocompletion is installed for autoloading.

---

## Configuration

The following environment variables can be used for configuring `chtf`. Click to expand.

<details>
<summary><strong><code>CHTF_TERRAFORM_DIR</code></strong> - Specifies where the Terraform versions are stored.</summary>

Defaults to the Homebrew Caskroom if the "tmatilai/terraforms" Tap is installed, `$HOME/.terraforms/` otherwise.
Each version should be installed as `$CHTF_TERRAFORM_DIR/terraform-<version>/terraform`.

</details>
<details>
<summary><strong><code>CHTF_AUTO_INSTALL</code></strong> - Controls automatic installation missing Terraform versions.</summary>

Possible values are: `yes`, `no`, and `ask`.
The default is `ask`, which will prompt the user for confirmation before automatic installation.

</details>
<details>
<summary><strong><code>CHTF_AUTO_INSTALL_METHOD</code></strong> - Specifies the method used for automatic installation.</summary>

The default is `homebrew` if `CHTF_TERRAFORM_DIR` is no specified and the "tmatilai/terraforms" Tap is installed, `zip`  otherwise.
There shouldn't be normally need to set this variable.

</details>

### Activating the `chtf` command

After installing, `chtf` has to be loaded to the shell.

#### fish

The fish version is [autoloaded](https://fishshell.com/docs/current/tutorial.html#autoloading-functions) so there is nothing more to do!

#### bash and zsh

The base directory on the following examples depends how and where `chtf` is installed. This assumes `make install`. With Homebrew, replace `$HOME` with the output of `brew --prefix`.

New shell session has to be started for the changes to take effect.

Add the following to the `~/.bashrc` or `~/.zshrc`:

```bash
######################################################################
# chtf

# Uncomment and change the value to override the default:
#CHTF_AUTO_INSTALL="ask" # yes/no/ask

if [[ -f "$HOME/share/chtf/chtf.sh" ]]; then
    source "$HOME/share/chtf/chtf.sh"
fi
```

## Usage

List all installed Terraform versions:

    chtf

Select the wanted Terraform version, for example:

    chtf 0.13.5

Use the Terraform version installed globally outside `chtf` (e.g. via a package manager):

    chtf system

### Tips

<details>
<summary><strong>Customized install</strong></summary>

`make install` installs `chtf` by default to the user's `$HOME` directory. But if installed as a root user (e.g. via `sudo`), the default location is `/usr/local` for system wide use. In both cases the wanted location can be specified with `PREFIX`. For example:

    sudo make install PREFIX=/opt

The development version of `chtf` can be used either by `source`ing or `make install`ing from a [clone of this repository](https://docs.github.com/en/free-pro-team@latest/github/creating-cloning-and-archiving-repositories/cloning-a-repository), or with Homebrew:

    brew install tmatilai/terraforms/chtf --HEAD

</details>
<details>
<summary><strong>Automatic switching on new shell session</strong></summary>

If you want to have a default Terraform version selected when starting a new shell session, you can of course add `chtf <version>` to the config file after loading `chtf`.
A bit more flexible way is to write the wanted version number to a file named `~/.terraform-version`, and read that.

```bash
# bash and zsh
if [[ -f "$HOME/.terraform-version" ]]; then
    chtf "$(< "$HOME/.terraform-version")"
fi
```

```fish
# fish
if test -f $HOME/.terraform-version
    chtf (cat $HOME/.terraform-version)
end
```

</details>
<details>
<summary><strong>Uninstalling Terraform versions</strong></summary>

Homebrew installed Terraform versions can be uninstalled with:

    brew uninstall --cask terraform-<version>

Note that the `<version>` uses dashes instead of dots for versions installed with `chtf` v2.2.0 and newer.

Otherwise installed versions can be uninstalled by deleting the directory:

    rm -r "$CHTF_TERRAFORM_DIR/terraform-<version>"

</details>
<details>
<summary><strong>Uninstalling chtf</strong></summary>

Homebrew installed `chtf` can be uninstalled with:

    brew uninstall chtf

`chtf` installed with `make` can be uninstalled by deleting the directory:

    rm -r "$HOME/share/chtf" # or where it was installed

</details>

---

## Contributing

Bug reports, pull requests, and other contributions are welcome on GitHub at [https://github.com/tmatilai/chtf](https://github.com/tmatilai/chtf).

This project is intended to be a safe, welcoming space for collaboration. By participating in this project you agree to abide by the terms of [Contributor Code of Conduct](CODE_OF_CONDUCT.md).

---

## Licence and Credits

The project is released as open source under the terms of the [MIT License](LICENSE).

Original idea and implementation of `chtf` was heavily affected by [chruby](https://github.com/postmodern/chruby).

Included [terraform-installer](https://github.com/robertpeteuil/terraform-installer) is released under the [Apache 2.0 License](https://github.com/robertpeteuil/terraform-installer/blob/1.5.4/LICENSE).

_NOTE: `chtf` was originally part of the [homebrew-terraforms](https://github.com/tmatilai/homebrew-terraforms/) project, but has been extracted to own project and modified to support also non-Homebrew environments._

# Omarchy on Ubuntu via Nix

This gives you the full [Omarchy](https://omarchy.org) desktop on a normal Ubuntu
install. Omarchy is a Hyprland setup by Basecamp with its own bar, launcher, lock
screen, menus and themes. Here it comes as a [Home Manager](https://github.com/nix-community/home-manager)
module, so everything is installed through Nix and nothing in Ubuntu itself is
replaced. GNOME stays as it is. At the login screen you pick Omarchy from the
gear menu, and GDM remembers your choice.

No drivers are touched. Nix built programs talk to the graphics driver Ubuntu
already has, through a small shim called nixGL.

## Quick start on a fresh machine

You need Ubuntu Desktop with a user account and sudo. Then:

```bash
git clone https://github.com/adam-abed-abud/omarchy-ubuntu-nix.git
cd omarchy-ubuntu-nix
./bootstrap.sh
```

The script installs Nix, builds the desktop, and writes the handful of system
files that need root: the login screen entry, the lock screen's PAM service, the
screen sharing portal, and an AppArmor profile. It asks for your sudo password
along the way. Expect a few gigabytes of downloads. It is safe to run again.

When it finishes, log out, click the gear icon on the login screen, choose
Omarchy, and log in. Press Super and K to see all keybindings.

If you have an NVIDIA card with the proprietary driver, make one change before
running the script. Open `home.nix` and set the wrapper to nvidia:

```nix
targets.genericLinux.nixGL.defaultWrapper = "nvidia";
```

Intel and AMD cards work with the default, which is mesa.

## Adding Omarchy to your own Home Manager setup

If you already manage your machine with Home Manager, you do not need the
example configuration. Import the module in your flake:

```nix
inputs.omarchy-ubuntu.url = "github:adam-abed-abud/omarchy-ubuntu-nix";
inputs.omarchy-ubuntu.inputs.nixpkgs.follows = "nixpkgs";

# in your homeManagerConfiguration
modules = [ inputs.omarchy-ubuntu.homeModules.omarchy ./home.nix ];
```

Your nixpkgs has to be nixos-unstable, because Omarchy needs a recent Hyprland
and Quickshell. Then turn it on in your home.nix:

```nix
omarchy.enable = true;
targets.genericLinux.nixGL.defaultWrapper = "mesa";   # or "nvidia"
nixpkgs.config.allowUnfree = true;
```

Finally run the bootstrap script from this repo and point it at your flake, so
it can write the root owned files:

```bash
./bootstrap.sh /path/to/your/flake#yourname
```

## Everyday use

Apply a change to your configuration:

```bash
home-manager switch --flake .#$USER --impure
```

Update everything to the latest pinned versions:

```bash
nix flake update
home-manager switch --flake .#$USER --impure
```

Go back to an earlier version if something broke:

```bash
home-manager generations
```

The `--impure` flag is only needed with the nvidia wrapper, which reads the
installed driver version while building. It does no harm otherwise. After an
NVIDIA driver upgrade, run the switch again.

Config files in `~/.config` are read only links into the Nix store. That is on
purpose. Edit the files in this repo (or in your flake) and run the switch again.

## Monitors, scale and keybindings

Omarchy keeps the parts you are meant to edit in a few Lua files: monitors,
input, keybindings, look and feel, and autostart. The defaults are in the
`hypr/` folder. Edit them there if you use the example configuration. If you
use your own flake, copy the folder into it and tell the module where it is:

```nix
omarchy.hyprDir = ./hypr;
```

The one setting most people need is the scale in `hypr/monitors.lua`. Set it to
1 for a normal 1080p screen and 2 for a HiDPI screen.

## What is different from Omarchy on Arch

Omarchy is pinned at version 4.0.4 and runs unmodified, with three deliberate
differences. Updates go through `nix flake update` instead of pacman, so the
update entry in the menu only points you there. The install menus that rely on
pacman do not work. Boot theming, fingerprint unlock and Voxtype are not
included.

The module installs the desktop and Chromium, nothing more. Your editor, PDF
viewer, media player and other apps are your choice and go in your own
configuration.

## What is in this repo

`flake.nix` pins every input to an exact version and exports the module as
`homeModules.omarchy`. `modules/omarchy.nix` is the module itself. `hypr/`
holds the default Hyprland Lua files. `home.nix` is the example configuration
used by the quick start. `bootstrap.sh` is the installer. `patches/` holds a
fix for nixGL on NVIDIA, explained below.

## Credits

Omarchy is by Basecamp and is used as is. This repo only changes how it is
installed and started on Ubuntu.

nixGL by the nix-community lets Nix built programs use the host's graphics
driver. Upstream has been quiet since late 2025, so this flake pins
[a branch that collects the open fixes](https://github.com/nix-community/nixGL/pull/226).
On top of that, the patch in `patches/` makes the NVIDIA wrapper export
`GBM_BACKENDS_PATH`, without which Hyprland cannot start (see
[nixGL #210](https://github.com/nix-community/nixGL/pull/210)), and ships the
EGL platform libraries that Wayland apps need inside a Nix process.

## License

MIT, see `LICENSE`. Omarchy and nixGL keep their own licenses.

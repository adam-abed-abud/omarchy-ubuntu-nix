# Omarchy on Ubuntu, via Nix

The full [Omarchy](https://omarchy.org) v4 Hyprland desktop — Quickshell
bar, lock screen, menus, themes and all — running on a stock Ubuntu
Desktop install, packaged as a [Home Manager](https://github.com/nix-community/home-manager)
module. Ubuntu's GNOME stays the default session; Omarchy is picked from
the gear menu on the login screen (GDM then remembers whichever session
you used last). Nothing here installs or changes drivers.

This repo is only the desktop layer. Your own software (shell, editor,
terminal, apps) lives in your own Home Manager configuration, which
imports this module.

```
flake.nix / flake.lock   inputs pinned to exact versions; exports
                         homeModules.omarchy and a minimal example config
modules/omarchy.nix      the Omarchy desktop port (packages, config links,
                         shims, GDM session script, patched nixGL)
hypr/                    the Hyprland Lua files Omarchy treats as user-owned
                         (monitors, input, keys, look, autostart); default seed
patches/                 fix for upstream nixGL's NVIDIA wrapper (see Credits)
bootstrap.sh             one-shot installer for a fresh machine
home.nix                 the example configuration: Omarchy and nothing else
```

## Use it from your own flake

```nix
# flake.nix
inputs.omarchy-ubuntu.url = "github:<you>/<this repo>";
# nixpkgs must be nixos-unstable: Omarchy v4 needs Hyprland 0.56+ / Quickshell 0.3+
inputs.omarchy-ubuntu.inputs.nixpkgs.follows = "nixpkgs";

# in homeManagerConfiguration:
modules = [ inputs.omarchy-ubuntu.homeModules.omarchy ./home.nix ];
```

```nix
# home.nix
omarchy.enable = true;
targets.genericLinux.nixGL.defaultWrapper = "nvidia";   # or "mesa" for Intel/AMD
nixpkgs.config.allowUnfree = true;                      # NVIDIA userspace libs, chromium codecs
# omarchy.hyprDir = ./hypr;   # your copy of this repo's hypr/, to change monitors/keys
```

Then, on the machine:

```bash
git clone <this repo> && cd <this repo>
./bootstrap.sh /path/to/your/flake#name
```

The script installs Nix, runs `home-manager switch` on your flake, and
writes the few root-owned files Nix can't: the GDM session entry, PAM for
the lock screen plus a `/run/wrappers/bin/unix_chkpwd` symlink for it,
screen-share portal registration, a `/usr/share/omarchy` symlink to the
Nix-linked Omarchy tree, an AppArmor profile so Nix's bubblewrap may
create user namespaces (Nautilus/Evince thumbnails), and Docker. It makes
zsh the login shell if your flake installs one. Safe to re-run. Log out
afterwards and pick "Omarchy (Hyprland)" from the gear menu.

Run it with no argument to get the example configuration in `home.nix`:
Omarchy alone, for the login name set as `user` in `flake.nix`.

Two things to check on new hardware: GPU → `defaultWrapper` (`"nvidia"`
for the proprietary NVIDIA driver, `"mesa"` for Intel/AMD); monitor →
`omarchy_gdk_scale` in `hypr/monitors.lua` (1 for a regular 1080p screen,
2 for HiDPI). The nvidia wrapper reads the installed driver version at
build time, so every switch needs `--impure`, and a driver upgrade means
re-running the switch. nixGL is a userspace shim that points Nix-built
apps at the host's existing GL libraries.

## Day to day

```bash
home-manager switch --flake <ref> --impure                       # apply changes
nix flake update && home-manager switch --flake <ref> --impure   # upgrade all
home-manager generations                                         # roll back
```

Config files are read-only links into the Nix store on purpose: edit the
files in your flake, not in `~/.config`, then re-run switch.

## Omarchy

The pinned Omarchy repo (v4.0.4) is linked to `~/.local/share/omarchy`
and runs its own scripts, Lua Hyprland config and Quickshell shell
unmodified. Start with `Super + K` (all keybindings). Common ones:
`Super + Space` launcher, `Super + Alt + Space` menu, `Super + Return`
terminal, `Super + Shift + Ctrl + Space` themes, `Print` screenshot. Bar
widgets are clickable; bar layout and plugins live in
`~/.config/omarchy/shell.json`.

Module options: `omarchy.enable`, `omarchy.hyprDir` (your Hyprland Lua
files), `omarchy.nixGL.provide` (set false to bring your own nixGL
package set).

Differences from Omarchy on Arch, all deliberate: updates go through
`nix flake update` (the `omarchy-update` menu entry says so); the
pacman-based `Install >` menus don't work; no Plymouth/SDDM boot theming,
fingerprint unlock or Voxtype. Default apps that Omarchy's keybindings
and MIME defaults expect but that are *your* choice (editor, PDF viewer,
media player, browser other than Chromium) are not installed by the
module.

## Credits and origins

- [Omarchy](https://omarchy.org) by Basecamp — pinned unmodified; this repo
  only adapts how it is installed and launched on Ubuntu.
- [nixGL](https://github.com/nix-community/nixGL) provides the GPU access
  for Nix-built apps on a non-NixOS host. Upstream has been dormant since
  late 2025, so the flake pins [catouc's aggregate branch](https://github.com/nix-community/nixGL/pull/226)
  of the open fixes (current nixpkgs compatibility, NVIDIA 59x version
  parsing). On top of that, `patches/nixgl-nvidia-gbm-backends.patch`
  makes the NVIDIA wrapper export `GBM_BACKENDS_PATH` (without it Hyprland
  cannot create a GBM allocator; cf. [nixGL #210](https://github.com/nix-community/nixGL/pull/210))
  and ship the Nix-built `egl-wayland`/`egl-gbm`/`egl-x11` platform
  libraries (without them EGL on Wayland fails for every Nix app, because
  the host's platform libraries cannot be loaded into a Nix process).

## License

MIT, see `LICENSE`. Omarchy and nixGL keep their own licenses.

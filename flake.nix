{
  # A flake is a self-describing Nix project: this file declares exactly which
  # inputs (dependency snapshots) it uses and which outputs it produces.
  # `flake.lock` pins every input to an exact git revision + content hash,
  # which is what makes the whole setup reproducible on any machine.
  description = "The Omarchy v4 Hyprland desktop on Ubuntu, as a Home Manager module";

  inputs = {
    # The package collection. Unstable because Omarchy v4 needs Hyprland 0.56+
    # (native Lua config) and Quickshell 0.3+, which the stable release
    # branch does not have yet.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager: declarative management of a *user* environment
    # (packages + dotfiles + services), independent of the host distro.
    home-manager = {
      url = "github:nix-community/home-manager";
      # Make home-manager use OUR nixpkgs instead of its own copy,
      # so everything is built from one coherent package set.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixGL: OpenGL shim for running Nix-built GUI apps on non-NixOS distros.
    # Nix apps link against Nix's own libGL, which doesn't know about the
    # host's GPU drivers; nixGL wraps the app so it finds them.
    # Upstream nixGL (nix-community) has been unmaintained since late 2025 and
    # breaks against current nixpkgs (nvidia_x11 dropped the `kernel`
    # argument) and against NVIDIA 59x drivers (new NVRM version-string
    # format). This fork is the aggregate of the open upstream fixes (nixGL
    # PRs #221-#223, collected in PR #226). Only its source is used; the
    # module builds it against the importing configuration's nixpkgs, with
    # patches/nixgl-nvidia-gbm-backends.patch applied.
    nixgl = {
      url = "github:catouc/nixGL";
      flake = false;
    };

    # Omarchy (DHH's Arch+Hyprland setup), pinned to a v4 release. v4's
    # centerpiece is omarchy-shell: one Quickshell instance providing the top
    # bar, OSD, lock screen, notifications, clipboard, menus and a plugin
    # system (replacing v3's waybar/mako/swayosd/walker). Its Lua Hyprland
    # configs are the compositor's native format since Hyprland 0.55, so
    # they run unmodified on Ubuntu. Not a flake: we only want its config
    # files, QML shell, themes, and helper scripts. The module links the
    # whole tree to ~/.local/share/omarchy, exactly where its scripts expect.
    omarchy = {
      url = "github:basecamp/omarchy/v4.0.4";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, nixgl, omarchy, ... }:
    let
      system = "x86_64-linux";

      # The module, with the two pinned sources bound in.
      omarchyModule = import ./modules/omarchy.nix { inherit omarchy nixgl; };

      # The login name the EXAMPLE configuration below is for. Only used by
      # that example; a flake that imports homeModules.omarchy sets its own.
      user = "adam";
    in {
      # --- The reusable part ---------------------------------------------
      # In your own Home Manager flake:
      #   inputs.omarchy-ubuntu.url = "github:<you>/<this repo>";
      #   ...
      #   modules = [ inputs.omarchy-ubuntu.homeModules.omarchy ./home.nix ];
      # and in home.nix:
      #   omarchy.enable = true;
      #   targets.genericLinux.nixGL.defaultWrapper = "nvidia";  # or "mesa"
      # Then run bootstrap.sh from this repo with your flake reference, for
      # the root-owned files (GDM entry, PAM, portal, AppArmor).
      homeModules = {
        omarchy = omarchyModule;
        default = omarchyModule;
      };

      # --- A minimal standalone configuration ----------------------------
      # Omarchy and nothing else: what bootstrap.sh applies when run without
      # a flake reference. Apply with:
      #   home-manager switch --flake .#$USER --impure
      homeConfigurations.${user} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          # Chromium codecs, and the NVIDIA userspace libraries nixGL's
          # nvidia wrapper builds.
          config.allowUnfree = true;
        };
        extraSpecialArgs = { inherit user; };
        modules = [ self.homeModules.omarchy ./home.nix ];
      };
    };
}

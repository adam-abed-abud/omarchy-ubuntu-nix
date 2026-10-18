# The Omarchy v4 (https://omarchy.org) Hyprland experience, ported to
# Home Manager on Ubuntu. Strategy:
#
#   * The pinned Omarchy repo (flake input, v4.0.4) is linked wholesale to
#     ~/.local/share/omarchy ($OMARCHY_PATH) — where its helper scripts,
#     Lua Hyprland configs, QML shell, theme templates and themes expect
#     to live.
#   * v4's desktop is `omarchy-shell`: ONE Quickshell instance providing the
#     top bar, OSD, lock screen, notifications, clipboard history, menus,
#     launcher and a plugin system. It replaced v3's waybar, mako, swayosd,
#     walker, hyprlock, hypridle, swaybg and the polkit agent.
#   * Hyprland is configured in Lua — the compositor's native config format
#     since 0.55 — straight from Omarchy's files. That needs Hyprland 0.56+
#     and Quickshell 0.3+, i.e. nixpkgs-unstable at the time of writing.
#   * GL-heavy apps are wrapped with nixGL because this is not NixOS. The
#     module provides a patched nixGL package set (see flake.nix); the host
#     picks the wrapper with targets.genericLinux.nixGL.defaultWrapper.
#   * Tiny shims in ~/.local/share/omarchy-nix/bin paper over the remaining
#     Arch-isms (uwsm, pacman updates). v4 itself uses NetworkManager, so
#     no Wi-Fi shim is needed on Ubuntu anymore.
#
# The pieces that need root (GDM session entry, PAM for the shell's lock
# screen, screen-sharing portal registration, AppArmor for bubblewrap) live
# in bootstrap.sh.
#
# This file is a function of two flake inputs, bound in flake.nix, that
# returns an ordinary Home Manager module (exported as homeModules.omarchy).
# Importing it only adds options; nothing is installed until
# `omarchy.enable = true`.
{ omarchy, nixgl }:
{ config, pkgs, lib, ... }:

let
  cfg = config.omarchy;
  wrapGL = config.lib.nixGL.wrap;

  home = config.home.homeDirectory;
  omarchyPath = "${home}/.local/share/omarchy";
  shimPath = "${home}/.local/share/omarchy-nix/bin";

  # Writable symlink target (outside the store) for files the theme switcher
  # regenerates on every theme change.
  mkLink = config.lib.file.mkOutOfStoreSymlink;

  # Helpers for the shim scripts that shadow/replace upstream Omarchy bins.
  shimRel = name: ".local/share/omarchy-nix/bin/${name}";
  shim = script: {
    executable = true;
    text = "#!/bin/bash\n" + script;
  };

  # "Keep only your personal overrides here": Omarchy treats these as
  # user-owned, so they come from `omarchy.hyprDir` (this repo's hypr/ by
  # default, seeded from upstream v4.0.4).
  userHypr = name: cfg.hyprDir + "/${name}";

  # nixGL built from THIS package set, from a patched source: the NVIDIA
  # wrapper must also export GBM_BACKENDS_PATH (Nix's Mesa only looks in
  # /run/opengl-driver/lib/gbm, a NixOS path; without it Hyprland dies with
  # "Cannot create a GBM Allocator" — nixGL PR #210, unmerged) and ship the
  # Nix-built EGL platform libraries (the host's cannot be loaded into a Nix
  # process). Building it here rather than taking nixGL's own flake output
  # also lets it see the host's allowUnfree setting, which the NVIDIA
  # userspace libraries need.
  nixglPkgs = import "${pkgs.applyPatches {
    name = "nixgl-patched";
    src = nixgl;
    patches = [ ../patches/nixgl-nvidia-gbm-backends.patch ];
  }}/default.nix" {
    inherit pkgs;
    enable32bits = true;
    enableIntelX86Extensions = true;
  };

  hyprland = wrapGL pkgs.hyprland;        # 0.56.x, native Lua config
  quickshell = wrapGL pkgs.quickshell;    # 0.3.x, runs omarchy-shell
  xdph = pkgs.xdg-desktop-portal-hyprland;
in
{
  options.omarchy = {
    enable = lib.mkEnableOption "the Omarchy Hyprland desktop (Ubuntu port)";

    hyprDir = lib.mkOption {
      type = lib.types.path;
      default = ../hypr;
      description = ''
        Directory with the user-owned Hyprland Lua files Omarchy expects you
        to edit: hyprland.lua, monitors.lua, input.lua, bindings.lua,
        looknfeel.lua, autostart.lua and .luarc.json. Copy this repo's hypr/
        into your own flake and point here to customize monitors, scale,
        keybindings or autostart.
      '';
    };

    nixGL.provide = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Set targets.genericLinux.nixGL.packages (with mkDefault) to the
        patched nixGL package set this module builds. You still choose the
        wrapper with targets.genericLinux.nixGL.defaultWrapper: "nvidia"
        for the proprietary NVIDIA driver (needs allowUnfree and --impure
        on switch, since it reads the installed driver version), "mesa"
        for Intel/AMD. Disable to supply your own nixGL packages.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Non-NixOS host: XDG_DATA_DIRS for Nix desktop entries, session vars.
    targets.genericLinux.enable = lib.mkDefault true;
    targets.genericLinux.nixGL.packages = lib.mkIf cfg.nixGL.provide (lib.mkDefault nixglPkgs);

    # Make the fonts installed below visible to fontconfig.
    fonts.fontconfig.enable = lib.mkDefault true;

    # Omarchy scripts find their siblings and $OMARCHY_PATH through these.
    # (Shims first so they can shadow same-named upstream scripts.)
    home.sessionPath = [ shimPath "${omarchyPath}/bin" ];
    home.sessionVariables.OMARCHY_PATH = omarchyPath;

    # -------------------------------------------------------------------------
    # Packages — mirrors install/omarchy-base.packages, minus Arch system
    # pieces (pacman, plymouth, sddm, ufw, iwd/impala — v4 uses
    # NetworkManager, which Ubuntu already runs) and minus personal software,
    # which belongs in the importing configuration.
    # -------------------------------------------------------------------------
    home.packages = [
      # Compositor + the Quickshell-based omarchy-shell. Hyprland MUST be
      # GL-wrapped on non-NixOS (official guidance:
      # https://wiki.hypr.land/Nix/Hyprland-on-other-distros/), and the shell
      # is a QtQuick app rendering on the GPU, so it gets the same treatment.
      hyprland
      quickshell               # provides `quickshell` and `qs` (IPC)
      pkgs.hyprpicker
      pkgs.hyprsunset
      xdph                     # screenshot/screencast portal backend

      # Screenshots / recordings / OCR / clipboard (annotation & clipboard
      # history now live inside the shell)
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
      (wrapGL pkgs.gpu-screen-recorder)
      pkgs.tesseract           # omarchy-capture-text (OCR)

      # Script + shell-widget dependencies
      pkgs.gum                 # pretty menus in omarchy-* scripts
      pkgs.jq
      pkgs.socat               # hyprland event watcher
      pkgs.fzf
      pkgs.imagemagick
      pkgs.brightnessctl
      pkgs.playerctl
      pkgs.pamixer
      pkgs.libnotify           # notify-send, used everywhere
      pkgs.udiskie             # automount (v4 autostart)
      pkgs.xdg-terminal-exec   # Super+Return → terminal indirection
      pkgs.terminaltexteffects # `tte`, powers the terminal screensaver
      pkgs.btop                # Super+Ctrl+T activity panel
      pkgs.fastfetch

      # Default Omarchy GUI apps
      pkgs.foot                # v4's default terminal (CPU-rendered, themed)
      (wrapGL pkgs.alacritty)  # also configured/themed; handy alternative
      (wrapGL pkgs.chromium)   # default browser; webapp bindings use --app=
      pkgs.nautilus            # Super+Shift+F file manager
      pkgs.gnome-calculator
      pkgs.imv                 # image viewer used by background/image pickers

      # Fonts the configs ask for
      pkgs.nerd-fonts.jetbrains-mono
      pkgs.liberation_ttf
      pkgs.font-awesome
    ];

    # -------------------------------------------------------------------------
    # Configs. Hyprland's Lua files are the ones Omarchy designates as
    # user-owned → they come from `omarchy.hyprDir` (autostart.lua carries
    # one Ubuntu adaptation hook). The rest links straight from the pinned
    # repo.
    # -------------------------------------------------------------------------
    xdg.configFile = {
      "hypr/hyprland.lua".source = userHypr "hyprland.lua";
      "hypr/monitors.lua".source = userHypr "monitors.lua";
      "hypr/input.lua".source = userHypr "input.lua";
      "hypr/bindings.lua".source = userHypr "bindings.lua";
      "hypr/looknfeel.lua".source = userHypr "looknfeel.lua";
      "hypr/autostart.lua".source = userHypr "autostart.lua";
      "hypr/.luarc.json".source = userHypr ".luarc.json";
      "hypr/hyprsunset.conf".source = "${omarchy}/config/hypr/hyprsunset.conf";
      "hypr/xdph.conf".source = "${omarchy}/config/hypr/xdph.conf";

      # Terminals (foot is the default via xdg-terminal-exec; the theme
      # switcher rewrites files under ~/.config/omarchy/current/theme/).
      "foot/foot.ini".source = "${omarchy}/config/foot/foot.ini";
      "alacritty/alacritty.toml".source = "${omarchy}/config/alacritty/alacritty.toml";
      "hyprland-xdg-terminals.list".source =
        "${omarchy}/default/xdg-terminal-exec/hyprland-xdg-terminals.list";

      # TUIs (v4 keeps the composed "current theme" under ~/.local/state)
      "btop/btop.conf".source = "${omarchy}/config/btop/btop.conf";
      "btop/themes/current.theme".source =
        mkLink "${home}/.local/state/omarchy/current/theme/btop.theme";

      # Chromium: Wayland/ozone flags
      "chromium-flags.conf".source = "${omarchy}/config/chromium-flags.conf";

      # Image viewer (used by the background picker)
      "imv/config".source = "${omarchy}/config/imv/config";

      # Prefer the Hyprland portal inside the Hyprland session, GTK elsewhere
      "xdg-desktop-portal/hyprland-portals.conf".text = ''
        [preferred]
        default=hyprland;gtk
      '';
    };

    # -------------------------------------------------------------------------
    # The Omarchy tree itself, its icon font, and the shims.
    # -------------------------------------------------------------------------
    home.file = {
      ".local/share/omarchy".source = omarchy;
      # Default MIME handlers, consulted last via XDG_DATA_DIRS (see
      # omarchy-session below). Upstream ships this file system-wide.
      ".local/share/omarchy-nix/xdg/applications/mimeapps.list".source =
        "${omarchy}/default/applications/mimeapps.list";
      ".local/share/fonts/omarchy".source = "${omarchy}/default/fonts/omarchy";

      # Omarchy launches apps through uwsm (universal wayland session
      # manager). We start Hyprland directly from GDM, so uwsm-app is a thin
      # wrapper and `uwsm stop` becomes a Hyprland exit.
      #
      # The wrapper also drops the nixGL variables that Hyprland inherited from
      # its own GL wrapper (LD_LIBRARY_PATH to Nix libglvnd/NVIDIA libs, EGL and
      # GBM search paths). Every app Hyprland spawns would otherwise inherit
      # them; Nix apps re-add them through their own nixGL wrapper, but Ubuntu
      # apps then mix Nix and host libraries (seen: /usr/bin/wezterm segfaulting
      # in the host libwayland-client).
      "${shimRel "uwsm-app"}" = shim ''
        [ "$1" = "--" ] && shift
        exec env -u LD_LIBRARY_PATH -u GBM_BACKENDS_PATH \
          -u __EGL_VENDOR_LIBRARY_FILENAMES -u __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS \
          "$@"
      '';
      "${shimRel "uwsm"}" = shim ''
        case "$1" in
          stop) exec hyprctl dispatch exit ;;
          app) shift; exec "$HOME/.local/share/omarchy-nix/bin/uwsm-app" "$@" ;;
          *) exit 0 ;;
        esac
      '';

      # Updates are flake-driven here, not git/pacman-driven.
      "${shimRel "omarchy-update"}" = shim ''
        echo "This Omarchy install is managed by Nix."
        echo "Update from the checkout of your configuration flake with:"
        echo "    nix flake update && home-manager switch --flake .#<name> --impure"
        read -r -p "Press enter to close"
      '';
      "${shimRel "omarchy-update-available"}" = shim ''
        # The bar's system-update widget polls this; exit 1 = "up to date".
        exit 1
      '';

      # Theme switching copies theme files out of the Nix store, and the
      # copies inherit the store's read-only mode bits, which breaks the NEXT
      # switch (its rm -rf can't delete them). On Arch this never happens
      # because /usr/share files are 644. Wrap the real script with a
      # permission fix before and after.
      "${shimRel "omarchy-theme-set"}" = shim ''
        state_dir="$HOME/.local/state/omarchy/current"
        [ -d "$state_dir" ] && chmod -R u+w "$state_dir" 2>/dev/null
        "$HOME/.local/share/omarchy/bin/omarchy-theme-set" "$@"
        rc=$?
        [ -d "$state_dir" ] && chmod -R u+w "$state_dir" 2>/dev/null
        exit $rc
      '';

      "${shimRel "omarchy-preview"}" = shim ''
        if [ "$#" -eq 0 ]; then
          echo "Usage: omarchy-preview <path>" >&2
          exit 2
        fi

        if [ "$#" -gt 1 ]; then
          echo "omarchy-preview: expected one path, got $#" >&2
          echo "Usage: omarchy-preview <path>" >&2
          exit 2
        fi

        first_path="$1"
        if [ ! -e "$first_path" ]; then
          echo "omarchy-preview: not found: $first_path" >&2
          exit 1
        fi

        if command -v sushi >/dev/null 2>&1; then
          exec sushi "$@"
        fi

        if [ -d "$first_path" ]; then
          command -v nautilus >/dev/null 2>&1 && exec nautilus --new-window "$first_path"
          command -v gio >/dev/null 2>&1 && exec gio open "$first_path"
          command -v xdg-open >/dev/null 2>&1 && exec xdg-open "$first_path"
          echo "omarchy-preview: no preview application found for $first_path" >&2
          exit 1
        fi

        mime=$(file -b --mime-type -- "$first_path" 2>/dev/null || true)
        case "$mime" in
          image/*)
            command -v imv >/dev/null 2>&1 && exec imv "$@"
            ;;
          application/pdf)
            command -v evince >/dev/null 2>&1 && exec evince "$@"
            command -v okular >/dev/null 2>&1 && exec okular "$@"
            ;;
          video/*|audio/*)
            command -v mpv >/dev/null 2>&1 && exec mpv "$@"
            command -v vlc >/dev/null 2>&1 && exec vlc "$@"
            ;;
        esac

        command -v gio >/dev/null 2>&1 && exec gio open "$first_path"
        command -v xdg-open >/dev/null 2>&1 && exec xdg-open "$first_path"
        echo "omarchy-preview: no preview application found for $first_path" >&2
        exit 1
      '';

      # Ubuntu/Nix session autostart, called from hypr/autostart.lua:
      # starts the portal backend (store path) and nudges Ubuntu's portal
      # daemon to pick it up.
      "${shimRel "omarchy-nix-autostart"}" = shim ''
        ${xdph}/libexec/xdg-desktop-portal-hyprland &
        (sleep 3 && systemctl --user restart xdg-desktop-portal.service) &
        exit 0
      '';

      # Session launcher used by the GDM entry bootstrap.sh installs.
      ".local/bin/omarchy-session" = {
        executable = true;
        text = ''
          #!/bin/bash
          # Launched by GDM (see /usr/share/wayland-sessions/omarchy.desktop).
          export PATH="${shimPath}:${omarchyPath}/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
          export OMARCHY_PATH="${omarchyPath}"
          export TERMINAL=xdg-terminal-exec
          if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
            . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
          fi
          # Omarchy's default MIME handlers (PDF -> Evince, images -> imv, video
          # -> mpv, text -> nvim, ...) go LAST, like the system-wide
          # /usr/share/applications/mimeapps.list the Arch package installs:
          # they only fill in types the user has not chosen a handler for, and
          # they apply to this session only, not to GNOME.
          export XDG_DATA_DIRS="$HOME/.nix-profile/share:$HOME/.local/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:$HOME/.local/share/omarchy-nix/xdg"
          # Launch the compositor directly. (Upstream's start-hyprland supervisor
          # re-execs through the nixGL wrapper, which breaks GDM's session-leader
          # tracking and makes the autologin session bounce. The only thing it
          # bought us was silencing the watchdog warning, which looknfeel.lua now
          # does via misc.disable_watchdog_warning.)
          exec Hyprland
        '';
      };
    };

    # -------------------------------------------------------------------------
    # First-run seeding. ~/.config/omarchy must stay writable: the shell edits
    # shell.json (plugins, bar layout) and the theme switcher composes
    # current/theme there. So these are copies/once-only, not store symlinks.
    # -------------------------------------------------------------------------
    home.activation.omarchySeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # shell.json, hooks, extensions, user theme dirs (no-clobber copy)
      run mkdir -p "$HOME/.config/omarchy/themes"
      run cp -rn ${omarchy}/config/omarchy/. "$HOME/.config/omarchy/" 2>/dev/null || true
      run chmod -R u+w "$HOME/.config/omarchy" 2>/dev/null || true

      # Hyprland toggle-flags state dir (hyprland.lua requires it to exist)
      if [ ! -f "$HOME/.local/state/omarchy/toggles/hypr/flags.lua" ]; then
        run mkdir -p "$HOME/.local/state/omarchy/toggles/hypr"
        run cp ${omarchy}/default/hypr/toggles/flags.lua "$HOME/.local/state/omarchy/toggles/hypr/"
        run chmod u+w "$HOME/.local/state/omarchy/toggles/hypr/flags.lua"
      fi

      # Initial theme (Tokyo Night, Omarchy's default) via Omarchy's own theme
      # switcher — through the permission-fixing shim, since the copies come
      # out of the read-only store. v4 composes the current theme under
      # ~/.local/state/omarchy/current. DBus/DISPLAY/XDG_RUNTIME_DIR are
      # blanked so its component restarts and gsettings calls no-op cleanly
      # during activation.
      if [ ! -e "$HOME/.local/state/omarchy/current/theme" ]; then
        OMARCHY_PATH="${omarchyPath}" \
        PATH="${shimPath}:${omarchyPath}/bin:${config.home.path}/bin:$PATH" \
        OMARCHY_THEME_SKIP_BACKGROUND=1 \
        DISPLAY= DBUS_SESSION_BUS_ADDRESS= XDG_RUNTIME_DIR= \
          run ${shimPath}/omarchy-theme-set tokyo-night 2>/dev/null || true
        first_bg=$(find -L "$HOME/.local/state/omarchy/current/theme/backgrounds" -type f 2>/dev/null | sort | head -1 || true)
        if [ -n "$first_bg" ]; then
          run ln -snf "$first_bg" "$HOME/.local/state/omarchy/current/background"
        fi
      fi
    '';
  };
}

# The example configuration: Omarchy on Ubuntu, no personal software.
# Copy and extend, or import homeModules.omarchy into your own flake instead.
{ config, pkgs, lib, user, ... }:

{
  # ---------------------------------------------------------------------------
  # Identity of this home environment
  # ---------------------------------------------------------------------------
  home.username = user;
  home.homeDirectory = "/home/${user}";

  # Compatibility marker: the Home Manager release these defaults were written
  # for. Do NOT bump it when you update inputs later; it is not a version pin.
  home.stateVersion = "26.05";

  # Let home-manager manage itself (provides the `home-manager` CLI after the
  # first activation).
  programs.home-manager.enable = true;

  # ---------------------------------------------------------------------------
  # The Omarchy desktop (modules/omarchy.nix)
  # ---------------------------------------------------------------------------
  omarchy.enable = true;

  # GPU access for Nix-built apps on a non-NixOS host. "mesa" covers
  # Intel/AMD; use "nvidia" for the proprietary NVIDIA driver (reads the
  # installed driver version at build time, so switch with --impure).
  # Nothing here installs or changes drivers.
  targets.genericLinux.nixGL.defaultWrapper = "mesa";

  # To change monitors, scale, keybindings or autostart: copy hypr/ somewhere
  # you own, edit, and point the module at it.
  # omarchy.hyprDir = ./my-hypr;

  # ---------------------------------------------------------------------------
  # Housekeeping
  # ---------------------------------------------------------------------------
  # Automatic garbage collection: a systemd *user* timer runs
  # nix-collect-garbage weekly, dropping profile generations older than 30
  # days and any store paths nothing references anymore. 30 days keeps a
  # month of instant rollbacks (`home-manager generations`).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}

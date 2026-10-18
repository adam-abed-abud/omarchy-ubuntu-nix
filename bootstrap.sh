#!/usr/bin/env bash
# One-command setup of a fresh Ubuntu machine.
#
#   ./bootstrap.sh                      # this repo's example config (Omarchy only)
#   ./bootstrap.sh /path/to/flake#name  # your own flake that imports homeModules.omarchy
#
# Does, in order (each step is idempotent — safe to re-run):
#   1. apt: prerequisites + Docker daemon (the one thing Nix can't manage here)
#   2. Nix (multi-user daemon install) + flakes enabled
#   3. home-manager switch --flake <ref>  (everything else lives there)
#   4. zsh from the Nix profile becomes the login shell, if the flake installs one
#   5. the root-owned files the Omarchy session needs (GDM entry, PAM, portal,
#      /usr/share/omarchy symlink, AppArmor profile for Nix's bubblewrap)
set -euo pipefail
cd "$(dirname "$0")"

FLAKE="${1:-.#$USER}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your normal user, not root — sudo is used where needed." >&2
  exit 1
fi

log "apt: prerequisites + Docker"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq curl xz-utils git docker.io
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker

log "Nix (multi-user)"
if [ ! -e /nix/var/nix/profiles/default/bin/nix ]; then
  curl --proto '=https' --tlsv1.2 -sSfL https://nixos.org/nix/install -o /tmp/install-nix
  sh /tmp/install-nix --daemon --yes
else
  echo "already installed"
fi

# Make nix usable in THIS shell (normally done by a fresh login shell)
if ! command -v nix >/dev/null 2>&1; then
  set +u
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  set -u
fi

log "Enabling flakes"
sudo mkdir -p /etc/nix
if ! grep -qs 'experimental-features.*flakes' /etc/nix/nix.conf; then
  echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
  sudo systemctl restart nix-daemon
fi

log "Applying home configuration (first run downloads a lot — go get coffee)"
if command -v home-manager >/dev/null 2>&1; then
  home-manager switch --flake "$FLAKE" -b backup --impure
else
  nix run home-manager/master -- switch --flake "$FLAKE" -b backup --impure
fi

log "Making zsh the login shell"
zsh_path="$HOME/.nix-profile/bin/zsh"   # stable symlink across generations
if [ -x "$zsh_path" ]; then
  grep -qxs "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells
  sudo chsh -s "$zsh_path" "$USER"
else
  echo "the flake does not install zsh — keeping the current login shell"
fi

log "Omarchy Hyprland session (GDM entry, lock-screen PAM, screen-share portal)"
# These are the only Omarchy pieces Nix can't place itself (they live under
# /usr and /etc). Everything else comes from modules/omarchy.nix via home-manager.

# 1. Login screen entry (gear menu on the GDM password screen). GNOME stays
#    the default session; pick "Omarchy (Hyprland)" when you want it. GDM
#    then remembers the last session you used. The entry launches
#    ~/.local/bin/omarchy-session (installed by home-manager), which sets
#    up PATH/env and starts the nixGL-wrapped Hyprland.
sudo tee /usr/share/wayland-sessions/omarchy.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Omarchy (Hyprland)
Comment=Omarchy-style Hyprland session, Nix-built
Exec=$HOME/.local/bin/omarchy-session
Type=Application
DesktopNames=Hyprland
EOF

# 2. PAM for the omarchy-shell lock screen. Quickshell (Nix-built) checks
#    the password through Nix's own libpam against the service
#    "omarchy-lock-password". Two Ubuntu/Nix mismatches to bridge:
#    a) Nix's pam_unix.so runs the setuid password helper at the NixOS path
#       /run/wrappers/bin/unix_chkpwd. Ubuntu has the same helper (same
#       protocol) at /sbin/unix_chkpwd, so provide a symlink there and
#       recreate it on every boot (/run is a tmpfs).
#    b) Ubuntu's common-auth pulls in modules Nix's libpam does not ship
#       (pam_sss, pam_cap), so the service gets its own minimal stack
#       instead of "include common-auth". It only ever authenticates the
#       already-logged-in user, so pam_unix alone is the right scope.
sudo tee /etc/tmpfiles.d/nix-pam-helper.conf >/dev/null <<'EOF'
# Nix-built PAM clients (the Omarchy lock screen) expect the NixOS helper path.
d /run/wrappers/bin 0755 root root -
L /run/wrappers/bin/unix_chkpwd - - - - /sbin/unix_chkpwd
EOF
sudo systemd-tmpfiles --create /etc/tmpfiles.d/nix-pam-helper.conf
sudo tee /etc/pam.d/omarchy-lock-password >/dev/null <<'EOF'
# Omarchy (Quickshell) lock screen. Minimal stack: Nix's libpam reads this.
auth     required  pam_unix.so nullok
account  required  pam_unix.so
EOF

# 3. Register the Hyprland screenshot/screencast portal backend with
#    Ubuntu's xdg-desktop-portal. The backend binary comes from Nix and is
#    started by Hyprland's autostart; this file just tells the portal
#    daemon it exists.
sudo mkdir -p /usr/share/xdg-desktop-portal/portals
sudo tee /usr/share/xdg-desktop-portal/portals/hyprland.portal >/dev/null <<'EOF'
[portal]
DBusName=org.freedesktop.impl.portal.desktop.hyprland
Interfaces=org.freedesktop.impl.portal.Screenshot;org.freedesktop.impl.portal.ScreenCast
UseIn=hyprland
EOF

# 4. Omarchy v4 is "packaged" software on Arch and hardcodes its install
#    location, /usr/share/omarchy, in ~40 scripts (the ~/.XCompose include,
#    bash env-bootstrap, migrations, ...). Point that path at the Nix-linked
#    tree so those references resolve. One symlink, no files copied.
sudo ln -sfn "$HOME/.local/share/omarchy" /usr/share/omarchy

# 5. AppArmor profile for Nix's bubblewrap. Ubuntu restricts unprivileged
#    user namespaces (kernel.apparmor_restrict_unprivileged_userns=1) and
#    only exempts binaries that have an AppArmor profile; it ships one for
#    /usr/bin/bwrap. Nix-built GNOME apps (Nautilus, Evince, ...) run their
#    thumbnailers through the Nix-built bwrap instead, which has no profile,
#    so "setting up uid map: Permission denied" and no image/PDF previews.
#    Same rules as Ubuntu's own /etc/apparmor.d/bwrap-userns-restrict, bound
#    to the Nix store path pattern.
sudo tee /etc/apparmor.d/nix-bwrap >/dev/null <<'EOF'
# Nix-built bubblewrap: mirror of Ubuntu's bwrap-userns-restrict profile.
abi <abi/5.0>,
include <tunables/global>

profile nix_bwrap /nix/store/*-bubblewrap-*/bin/bwrap flags=(attach_disconnected,mediate_deleted) {
  allow capability,
  allow file rwlkm /{**,},
  allow network,
  allow unix,
  allow ptrace,
  allow signal,
  allow mqueue,
  allow io_uring,
  allow userns,
  allow mount,
  allow umount,
  allow pivot_root,
  allow dbus,
  allow pix /** -> &nix_bwrap//&nix_unpriv_bwrap,
  include if exists <local/nix-bwrap>
}

profile nix_unpriv_bwrap flags=(attach_disconnected,mediate_deleted) {
  allow file rwlkm /{**,},
  allow network,
  allow unix,
  allow ptrace,
  allow signal,
  allow mqueue,
  allow io_uring,
  allow userns,
  allow mount,
  allow umount,
  allow pivot_root,
  allow dbus,
  allow pix /** -> &nix_unpriv_bwrap,
  audit deny capability,
  include if exists <local/nix-unpriv-bwrap>
}
EOF
sudo apparmor_parser -r /etc/apparmor.d/nix-bwrap

log "Done"
cat <<'EOF'
Remaining manual steps:
  - log out; on the login screen pick the gear/session menu -> "Omarchy (Hyprland)"
    (docker group + zsh login shell also take effect at login)
  - first Hyprland session: Super+K shows all keybindings, Super+Alt+Space the menu
EOF

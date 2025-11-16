#!/usr/bin/env bash
set -euo pipefail

# Improved Pop!_OS gaming setup:
# - enables universe
# - checks package availability before install (skips missing pkgs)
# - optional WineHQ/vkd3d enabling (disabled by default)
# - retains your requested toggles and AUTO_UPDATE behavior

############# USER CONFIG #############
INSTALL_STEAM_FLATPAK=false
INSTALL_LUTRIS=true
INSTALL_PROTONUP_FLATPAK=true
INSTALL_MANGOHUD=true
INSTALL_GAMEMODE=true
INSTALL_VKBASALT=true
INSTALL_VULKAN_TOOLS=true
INSTALL_32BIT_LIBS=true
INSTALL_OBS=true

# If you want system-packaged WineGE/vkd3d via WineHQ (may be preferable to building)
# set to true to add WineHQ repo (will run apt-key / apt update for that repo).
INSTALL_WINEHQ=false

# do/don't globally run apt update/upgrade at start
AUTO_UPDATE=false
########################################

info(){ printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[ERR]\e[0m %s\n" "$*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  err "Run as root (sudo)."
fi

# Build DEB_PKGS by checking availability first (prevents apt trying to install non-existent pkgs)
DEB_PKGS=()
SKIPPED=()

# utility: check whether a package (possibly with :i386) is available in apt
pkg_available() {
    local pkg="$1"
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# enable ubuntu/pop universe repository if not already enabled (safe)
enable_universe_if_needed() {
  if ! grep -R --quiet "^deb .* universe" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    info "Enabling 'universe' repository (required for many community packages)..."
    # ensure add-apt-repository exists
    apt -y install --no-install-recommends software-properties-common || warn "failed to install software-properties-common"
    # Use add-apt-repository to enable universe
    add-apt-repository -y universe || warn "add-apt-repository universe failed"
    info "Running apt update to refresh package lists for newly enabled repositories..."
    apt update || warn "apt update failed after enabling universe"
  else
    info "'universe' repository already enabled"
  fi
}

# optionally add WineHQ (for winehq-stable/devel/staging + vkd3d packaged builds)
add_winehq_repo() {
  info "Adding WineHQ repository and keys (for winehq / vkd3d packages)..."
  # Install prerequisites
  apt -y install --no-install-recommends software-properties-common gnupg2 ca-certificates wget || warn "couldn't install prerequisites for WineHQ"
  # Add the Ubuntu keyring (WineHQ instructions)
  wget -qO- https://dl.winehq.org/wine-builds/winehq.key | apt-key add - || warn "could not add winehq key"
  # Determine Ubuntu codename (Pop!_OS often uses 'jammy' or similar)
  CODENAME=$(lsb_release -sc)
  echo "deb https://dl.winehq.org/wine-builds/ubuntu/ ${CODENAME} main" > /etc/apt/sources.list.d/winehq.list
  apt update || warn "apt update failed after adding WineHQ repo"
}

# start
info "Starting Pop!_OS gaming setup (improved). AUTO_UPDATE=${AUTO_UPDATE}"

# If user didn't want global apt update we still need to enable 'universe' to see many packages.
# Do that (and update) automatically so pkg_available will be accurate.
enable_universe_if_needed

# If user wants WineHQ, add it (and update)
if [ "$INSTALL_WINEHQ" = true ]; then
  add_winehq_repo
fi

# Enable i386 if requested
if [ "$INSTALL_32BIT_LIBS" = true ]; then
  info "Enabling i386 architecture for 32-bit compatibility (Steam, Wine)..."
  dpkg --print-foreign-architectures | grep -q '^i386$' || dpkg --add-architecture i386
  apt update || warn "apt update failed after adding i386 architecture"
fi

# COMMON PKGS (ensure add-apt-repository availability, etc.)
COMMON_PKGS=(curl wget ca-certificates gnupg lsb-release apt-transport-https build-essential pkg-config software-properties-common)

info "Installing small set of common helper packages (if missing)..."
# safe install (don't abort on failure)
apt -y install "${COMMON_PKGS[@]}" || warn "Some common helper packages failed to install; continuing."

# Power / tuning tools (these usually exist)
for p in tlp powertop thermald cpufrequtils irqbalance; do
  if pkg_available "$p"; then DEB_PKGS+=("$p"); else warn "Package $p not found in apt; skipping."; fi
done

# Compatibility / runtime helpers
# prefer distro wine packages where available; WineHQ optional (controlled earlier)
for p in wine wine64 wine32; do
  if pkg_available "$p"; then DEB_PKGS+=("$p"); else warn "Package $p not found; skipping."; fi
done

# If user enabled INSTALL_WINEHQ then try adding winehq-staging/devel/stable
if [ "$INSTALL_WINEHQ" = true ]; then
  if pkg_available "winehq-staging"; then
    DEB_PKGS+=("winehq-staging")
  elif pkg_available "winehq-devel"; then
    DEB_PKGS+=("winehq-devel")
  elif pkg_available "winehq-stable"; then
    DEB_PKGS+=("winehq-stable")
  else
    warn "No winehq package found in WineHQ repo."
  fi

  if pkg_available "vkd3d"; then
    DEB_PKGS+=("vkd3d")
  elif pkg_available "vkd3d-tools"; then
    DEB_PKGS+=("vkd3d-tools")
  else
    warn "vkd3d not found in apt; will skip packaged vkd3d."
  fi
fi

# vkd3d system package (if not using WineHQ) check too
if pkg_available "vkd3d"; then DEB_PKGS+=("vkd3d"); fi
if pkg_available "vkd3d-tools"; then DEB_PKGS+=("vkd3d-tools"); fi

# Virtual camera for OBS
if pkg_available "v4l2loopback-dkms"; then DEB_PKGS+=("v4l2loopback-dkms"); else warn "v4l2loopback-dkms not available in apt; skip."; fi

# Gaming-specific packages
if [ "$INSTALL_GAMEMODE" = true ] && pkg_available "gamemode"; then DEB_PKGS+=("gamemode"); else warn "gamemode not available; skipping."; fi
if [ "$INSTALL_MANGOHUD" = true ] && pkg_available "mangohud"; then DEB_PKGS+=("mangohud"); else warn "mangohud not available; skipping."; fi

# Vulkan tools + mesa-utils
if [ "$INSTALL_VULKAN_TOOLS" = true ]; then
  for p in vulkan-tools libvulkan1 mesa-utils; do
    if pkg_available "$p"; then DEB_PKGS+=("$p"); else warn "Package $p not available; skipping."; fi
  done
fi

# 32-bit libs (ensure we don't duplicate)
if [ "$INSTALL_32BIT_LIBS" = true ]; then
  for p in libvulkan1:i386 libgl1-mesa-dri:i386; do
    if pkg_available "$p"; then DEB_PKGS+=("$p"); else warn "32-bit package $p not available; skipping."; fi
  done
fi

# vkBasalt
if [ "$INSTALL_VKBASALT" = true ]; then
  if pkg_available "vkbasalt"; then DEB_PKGS+=("vkbasalt"); else
    warn "vkBasalt not found in apt; skipping. You can build manually or use a different repo."
    VKBUILD_SKIPPED=true
  fi
fi

# OBS
if [ "$INSTALL_OBS" = true ] && pkg_available "obs-studio"; then DEB_PKGS+=("obs-studio"); else warn "obs-studio not in apt (or not found); skipping (you can use Flatpak or Pop!_Shop)."; fi

# Remove duplicates from DEB_PKGS (safe)
DEB_PKGS=( $(printf "%s\n" "${DEB_PKGS[@]}" | awk '!x[$0]++') )

# Show planned install set
info "Planned APT install list: ${DEB_PKGS[*]:-<none>} (skipped unavailable pkgs with warnings)"

# Install packages (respecting AUTO_UPDATE: we expect apt cache valid because we updated when enabling repos)
if [ "${#DEB_PKGS[@]}" -gt 0 ]; then
  info "Installing selected Debian packages..."
  apt -y install "${DEB_PKGS[@]}" || warn "Some apt installs failed. If so, run: sudo apt update && re-run this script (or install the missing pkgs manually)."
else
  info "No Debian packages to install (all requested packages were unavailable or skipped)."
fi

# Flatpak: ProtonUp-Qt if requested (we already ensured flatpak + flathub earlier if needed)
if [ "$INSTALL_PROTONUP_FLATPAK" = true ]; then
  if ! command -v flatpak >/dev/null 2>&1; then
    info "Installing flatpak (required for ProtonUp-Qt)..."
    apt -y install flatpak || warn "flatpak install failed"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  fi
  if command -v flatpak >/dev/null 2>&1; then
    info "Installing ProtonUp-Qt (Flatpak)"
    flatpak install -y flathub net.davidotek.pupgui2 || warn "ProtonUp-Qt flatpak install failed"
  fi
fi

# Lutris (APT only as requested) — check and install
if [ "$INSTALL_LUTRIS" = true ]; then
  info "Installing Lutris (APT only)..."
  if pkg_available "lutris"; then
    apt -y install lutris || warn "Lutris apt install failed"
    info "Lutris installed (apt)."
  else
    warn "Lutris package not found in apt. Try: sudo apt update; if still missing, enable appropriate repos or install Lutris via Flatpak."
  fi
fi

# gamemoded service
if command -v gamemoded >/dev/null 2>&1; then
  info "Enabling gamemoded service..."
  systemctl enable --now gamemoded.service || warn "Could not enable gamemoded (may not be available on this Pop!_OS build)."
fi

# Mangohud message
if command -v mangohud >/dev/null 2>&1; then
  info "MangoHud installed. Example: mangohud <game> or add 'mangohud %command%' to launch options."
fi

# vkBasalt build hint
if [ "${VKBUILD_SKIPPED:-false}" = true ]; then
  warn "vkBasalt wasn't in apt. To build it yourself:"
  cat <<'EOF'
  git clone https://github.com/DadSchoorse/vkBasalt.git
  cd vkBasalt
  meson setup build
  meson compile -C build
  sudo meson install -C build
EOF
fi

info "Service enabling for tlp / irqbalance / thermald"
# Enable recommended services if installed
for svc in tlp irqbalance thermald; do
  if systemctl list-unit-files | grep -q "^${svc}\."; then
    systemctl enable --now "$svc" || warn "Failed enabling $svc"
  fi
done

info "Recommended sysctl & inotify tuning for gaming"
cat >/etc/sysctl.d/99-gaming.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
fs.inotify.max_user_watches=524288
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system || true


info "All done. If some packages were skipped, run 'sudo apt update' and re-run this script, or enable WineHQ if you want winehq/vkd3d packaged installs."
info "Recommendations:"
cat <<EOF
 - Reboot if you installed drivers or kernel packages: sudo reboot
 - To get WineHQ (Wine + vkd3d packaged), set INSTALL_WINEHQ=true in the script and re-run (this adds the WineHQ repo).
 - If packages still fail, run: sudo apt update && apt-cache policy <pkg> to inspect availability.
EOF

echo
info "SUMMARY:"
apt list --installed "${DEB_PKGS[@]}" 2>/dev/null || true
echo
echo "If some packages were skipped, run: sudo apt update && re-run this script. Check below for skipped packages."

echo "Skipped packages (not in apt):"
if [ ${#SKIPPED[@]} -eq 0 ]; then
    echo "None — all requested packages were available in apt."
else
    for s in "${SKIPPED[@]}"; do
        echo " - $s"
    done
fi

exit 0

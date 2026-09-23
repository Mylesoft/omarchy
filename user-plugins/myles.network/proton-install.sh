#!/bin/bash
# Install Proton VPN CLI. Omarchy's mirror often stalls on large/extra packages,
# so this temporarily prefers Arch mirrors for the install, then restores yours.
set -uo pipefail

if pacman -Q proton-vpn-cli &>/dev/null && command -v protonvpn >/dev/null 2>&1; then
  echo "Proton VPN CLI is already installed."
  echo
  read -r -p "Press Enter to close…" _
  exit 0
fi

mirrorlist=/etc/pacman.d/mirrorlist
backup=/tmp/omarchy-mirrorlist.protonvpn.bak.$$

restore_mirrors() {
  if [[ -f $backup ]]; then
    sudo cp "$backup" "$mirrorlist"
    rm -f "$backup"
    echo "Restored original mirrorlist."
  fi
}
trap restore_mirrors EXIT

echo "Installing Proton VPN CLI…"
echo "Temporarily using Arch Linux mirrors (Omarchy mirror has been stalling)."
echo

sudo cp "$mirrorlist" "$backup"
sudo tee "$mirrorlist" >/dev/null <<'EOF'
# Temporary Arch mirrors for Proton VPN install — original restored on exit
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://mirror.omarchy.org/$repo/os/$arch
EOF

# Drop partial/corrupt downloads that make pacman retry the same bad file.
sudo rm -f /var/cache/pacman/pkg/python-pygments-*.pkg.tar.zst.part \
           /var/cache/pacman/pkg/*.part 2>/dev/null || true

# Prefetch the package that keeps stalling, with curl retries.
pyg=python-pygments-2.21.0-1-any.pkg.tar.zst
cache=/var/cache/pacman/pkg
if [[ ! -f $cache/$pyg ]]; then
  echo "Prefetching $pyg…"
  tmp=$(mktemp)
  if curl -fL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 300 \
      -o "$tmp" "https://geo.mirror.pkgbuild.com/extra/os/x86_64/$pyg"; then
    sudo mv "$tmp" "$cache/$pyg"
    echo "Cached $pyg"
  else
    rm -f "$tmp"
    echo "Prefetch skipped — pacman will download it."
  fi
fi

echo
ok=0
for i in 1 2 3; do
  echo "—— Attempt $i/3 ——"
  if sudo pacman -S --noconfirm --needed --disable-download-timeout proton-vpn-cli; then
    ok=1
    break
  fi
  echo
  echo "Failed. Retrying in 3s…"
  sleep 3
done

echo
if [[ $ok -eq 1 ]] && command -v protonvpn >/dev/null 2>&1; then
  echo "Installed. Close this window, reopen Network, then press Sign in."
  echo
  read -r -p "Press Enter to close…" _
  exit 0
fi

echo "Install failed after retries. You can try again later."
echo
read -r -p "Press Enter to close…" _
exit 1

#!/bin/bash
# Install Proton VPN CLI through Omarchy's package helper. This leaves the
# system mirror list and pacman cache untouched.
set -euo pipefail

if command -v protonvpn >/dev/null 2>&1 && pacman -Q proton-vpn-cli &>/dev/null; then
  echo "Proton VPN CLI is already installed."
  exit 0
fi

if ! command -v omarchy >/dev/null 2>&1; then
  echo "Omarchy's package helper is unavailable. Install proton-vpn-cli with your preferred Arch package helper." >&2
  exit 1
fi

echo "Installing Proton VPN CLI with Omarchy's package helper…"
omarchy pkg add proton-vpn-cli

if command -v protonvpn >/dev/null 2>&1 && pacman -Q proton-vpn-cli &>/dev/null; then
  echo "Proton VPN CLI installed. Reopen the network drawer and sign in."
  exit 0
fi

echo "Package installation finished, but the protonvpn command was not found." >&2
exit 1

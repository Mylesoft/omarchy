#!/bin/bash
# Interactive Proton VPN sign-in for the My Network panel.
set -euo pipefail

if ! command -v protonvpn >/dev/null 2>&1; then
  echo "protonvpn is not installed. Run: omarchy pkg add proton-vpn-cli" >&2
  exit 1
fi

echo "Proton VPN sign-in"
echo "Create a free account at https://account.proton.me/vpn if you need one."
echo
read -r -p "Proton email or username: " username
if [[ -z ${username} ]]; then
  echo "Cancelled." >&2
  exit 1
fi

exec protonvpn signin "$username"

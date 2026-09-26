# My Network for Omarchy

Version: 2.9.0
Plugin id: `myles.network`

## Install from this archive

Review the plugin files before enabling them. Omarchy plugins run inside the shell with your user account's permissions; this plugin can query and change NetworkManager connections when you use its controls.

1. Extract the archive. It creates a `myles.network` directory.
2. Open a terminal in the directory containing `myles.network` and run:

```bash
mkdir -p ~/.config/omarchy/plugins
cp -a myles.network ~/.config/omarchy/plugins/
omarchy plugin validate ~/.config/omarchy/plugins/myles.network
omarchy-shell shell rescanPlugins
omarchy plugin enable myles.network --section right
```

The last command enables the widget and places it in the bar's right section. If they prefer, your friend can choose another placement or move it later through Omarchy's bar controls.

If the widget does not appear, check `omarchy plugin list` and try `omarchy-shell shell rescanPlugins`. The plugin stores its own settings and saved profiles under `~/.local/state/omarchy/myles-network/`; this archive does not include that state. Saved Setup JSON transfers shortcut labels and VPN preference, not NetworkManager profiles or passwords. Wi-Fi shortcuts match by SSID and wired shortcuts by profile name when the same UUID is not present, so create the relevant local NetworkManager profile first.

## Update or remove

To install a newer archive, extract it and copy the updated files over the existing plugin, then rescan:

```bash
cp -a myles.network/. ~/.config/omarchy/plugins/myles.network/
omarchy plugin validate ~/.config/omarchy/plugins/myles.network
omarchy-shell shell rescanPlugins
```

To remove it, run `omarchy plugin disable myles.network`, then remove `~/.config/omarchy/plugins/myles.network`.

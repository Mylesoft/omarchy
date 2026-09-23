# Personal Omarchy Plugins

This directory is a versioned copy of the personal shell plugins from `~/.config/omarchy/plugins/`. It is kept outside `shell/plugins/` so the archive does not register duplicate widgets or change the active Omarchy runtime. The live plugins continue to load from the user config directory.

To install or restore a plugin, copy its directory to `~/.config/omarchy/plugins/<plugin-id>/`, then run `omarchy-shell shell rescanPlugins` or restart the shell.

The snapshot excludes empty plugin placeholders, the `omacom.elsewhen` symlink to the packaged Omarchy plugin, nested Git metadata, and generated Python bytecode/cache files. To refresh this archive after editing the live plugins, copy their source files here and commit the changes.

Included plugin bundles:
- `myles.agents`
- `myles.appearance-picker`
- `myles.calculator`
- `myles.clock`
- `myles.media`
- `myles.network`
- `myles.plugins`
- `myles.workspace-bundles`
- `myles.workspaces`
- `omacom.usage`

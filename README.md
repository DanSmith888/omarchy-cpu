# Cpu

CPU load, temperature and clock in the Omarchy bar — in the [Omarchy](https://omarchy.org/) bar.

TODO: one paragraph on what this targets and what it does not.

<!-- ![Bar](docs/bar.png) -->
<!-- ![Panel](docs/panel.png) -->

## Install

No setup, no root.

```bash
omarchy plugin add https://github.com/DanSmith888/omarchy-cpu.git --enable
```

### Check it

```bash
~/.config/omarchy/plugins/dansmith888.cpu/bin/cpuctl doctor
```

Verifies every link from the source to the bar and tells you how to fix
whatever is broken. Put `bin/` on your `PATH` if you want `cpuctl` as
a command.

## Update

```bash
omarchy plugin update dansmith888.cpu && omarchy restart shell
```

## Remove

```bash
omarchy plugin remove dansmith888.cpu
```

That removes everything. The plugin never touches anything outside its own
folder and a lock file in `$XDG_RUNTIME_DIR`.

## Using it

**Left-click** the pill to open the panel. **Middle-click** to force a
refresh. To open the panel from a hotkey, bind:

```bash
omarchy-shell shell toggle dansmith888.cpu
```

## What it does

TODO

## Requirements

- Omarchy (Quattro or later)
- TODO

## Command line

```
cpuctl get [--json]
cpuctl doctor
```

## Good to know

TODO: quirks and limits.

## What runs, and as whom

Omarchy plugins run inside the shell process, unsandboxed, as your user.
This one runs two Python scripts from its own `bin/` — standard library
only, no extra packages, no binaries, no network, nothing that needs root.
It writes nothing outside its folder except a lock file in
`$XDG_RUNTIME_DIR`.

## Licence

MIT — see [LICENSE](LICENSE).

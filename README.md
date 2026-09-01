# CPU

CPU load, temperature and clock in the [Omarchy](https://omarchy.org/) bar.

![Bar](docs/bar.png)

![Panel](docs/panel.png)

I built this for my own machine, alongside
[omarchy-gpu](https://github.com/DanSmith888/omarchy-gpu) and
[omarchy-bandwidth](https://github.com/DanSmith888/omarchy-bandwidth). The three
share a panel layout and controls.

## Install

```bash
omarchy plugin add https://github.com/DanSmith888/omarchy-cpu.git --enable
```

Update with `omarchy plugin update dansmith888.cpu && omarchy restart shell`.
Remove with `omarchy plugin remove dansmith888.cpu`.

## Using it

Left click opens the panel. Middle click opens `btop`. Hover for a summary.

Bind a hotkey with `omarchy-shell shell toggle dansmith888.cpu`.

## The panel

| Section | Shows |
|---|---|
| Hero | Model, cores, threads, top clock |
| Graph | Recent load, 30 to 240 samples |
| Meters | Load, package power, memory, load average |
| Cores | One bar per hardware thread |
| Temperature | Every sensor the CPU's hwmon reports |
| Top processes | Busiest since the last sample |
| In the bar | Which readings the pill shows, refresh rate, °C or °F |
| Power | Your CPU's PPT, which the power bar is measured against |
| Layout | A fixed pill width, or auto |
| Warning & alert | Two load thresholds, each with a colour from the active theme |

Settings live on the widget's `~/.config/omarchy/shell.json` entry and apply
immediately.

## Power

Power is off until you enter your CPU's **PPT** in the panel. At 0 there is no
power display at all.

It is read from the kernel's RAPL energy counter. Most kernels ship that
counter root only, as the mitigation for CVE-2020-8694, so there is usually
nothing to read and the plugin shows nothing rather than guessing. To grant
access, scoped to the `wheel` group:

```bash
sudo tee /etc/udev/rules.d/99-rapl-readable.rules >/dev/null <<'RULE'
SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", \
  RUN+="/usr/bin/chgrp wheel /sys%p/energy_uj", \
  RUN+="/usr/bin/chmod g+r /sys%p/energy_uj"
RULE
sudo udevadm trigger --subsystem-match=powercap
```

That relaxes a real mitigation: power readings are a side channel. Fine on a
single user desktop, a poor idea on a shared machine. Delete the rule file and
reboot to undo it. The plugin never asks for privileges either way.

Use PPT, not TDP. A Ryzen 9 3900X is 142 W PPT against 105 W TDP.

## Requirements

Omarchy (Quattro or later) and Linux with `/proc` mounted. `btop` only for the
middle click shortcut.

## Notes

Load is a delta between two samples. The first reading after a boot takes a
short second sample so it still means something.

Process percentages follow `top`: a share of one core, so four busy cores read
400%. The Load reading is the machine wide figure and is always 0 to 100%.

Used memory follows `MemAvailable`, so reclaimable cache is not counted.

Temperatures come from `k10temp`, `zenpower`, `coretemp`, `cpu_thermal` or
`acpitz`, whichever is present, with thermal zones as a fallback.

## Command line

```
cpuctl get [--json]        load, per-core, temperatures, clock, memory, top
cpuctl top [--json] [-n N] busiest processes
cpuctl doctor              check every link from /proc to the bar
```

## Tests

```bash
test/state-dir-safety.sh
```

Checks that the runtime state directory cannot be used to write through a
symlink, against a throwaway `XDG_RUNTIME_DIR` so live state is untouched.

## What runs, and as whom

Omarchy plugins run inside the shell process, unsandboxed, as your user. This
one runs two Python scripts from its own `bin/`: standard library only, no
extra packages, no binaries, no network, nothing needing root. It writes a lock
and a sample state file in `$XDG_RUNTIME_DIR` and nothing else outside its own
folder.

## Credits

The panel borrows its shape from Omarchy's tailscale and network panels, and
the history graph from
[stappmus.activity-monitor](https://github.com/stappmus/omarchy-activity-monitor).

## Licence

MIT, see [LICENSE](LICENSE).

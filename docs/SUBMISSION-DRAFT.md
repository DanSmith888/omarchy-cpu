<!--
Marketplace submission for https://plugins.omarchy.org — unsubmitted draft.
Before submitting: push the repo and tag v1.0.0, strip this comment, then:

  gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace \
    --title "[Plugin]: CPU" --body-file docs/SUBMISSION-DRAFT.md
-->

### Repository URL

https://github.com/DanSmith888/omarchy-cpu

### Category

Hardware

### Tags

bar, system, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

CPU load, temperature and clock in the bar; a load graph, a bar per hardware
thread, every temperature sensor the kernel exposes, memory, load average and
the busiest processes in the panel. Middle-click drops into btop.

Everything comes from `/proc` and `/sys` — no daemon, no root, no network, no
external binaries. Two standard-library Python scripts in `bin/`, one of which
imports the other in-process so a poll costs a single interpreter start. The
only thing written outside the plugin folder is a lock and a sample-state file
in `$XDG_RUNTIME_DIR`, so `omarchy plugin remove` is a clean uninstall.

Package power is read from RAPL when the kernel allows it. On a stock kernel
`energy_uj` is root-only (the PLATYPUS mitigation, CVE-2020-8694), so the
power readings are simply absent and the panel says so rather than asking for
privileges. The plugin never escalates and never asks for sudo.

One of a trio with omarchy-gpu and omarchy-network-speed, which share the same
panel layout and controls.

### Submission checklist

- [x] The repository is public and includes install and removal instructions
- [x] The license and any external dependencies are documented
- [x] I own or have permission to publish the plugin and preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing only and is not a security review

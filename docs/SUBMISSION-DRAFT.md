<!--
Marketplace submission, unsubmitted. To send: push, then
  gh issue create --repo HANCORE-linux/omarchy-plugin-marketplace \
    --title "[Plugin]: CPU" --body-file docs/SUBMISSION-DRAFT.md
(strip this comment first)
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

Load, temperature and clock in the bar. The panel adds a load graph, a bar per
hardware thread, every CPU temperature sensor the kernel exposes, memory, load
average and the busiest processes. Middle click opens btop.

Everything comes from /proc and /sys. Two standard library Python scripts in
bin/, no daemon, no root, no network, no binaries. It writes a lock and a
sample state file in $XDG_RUNTIME_DIR and nothing else outside its own folder,
so removal is clean.

Package power is optional and off by default. It reads the kernel's RAPL energy
counter, which most kernels keep root only as the mitigation for
CVE-2020-8694. Without access the plugin shows no power at all rather than
estimating, and it never asks for privileges. The README documents the one udev
rule that grants it and how to undo it.

One of a trio with omarchy-gpu and omarchy-bandwidth, which share a panel
layout and controls.

### Submission checklist

- [x] The repository is public and includes install and removal instructions
- [x] The license and any external dependencies are documented
- [x] I own or have permission to publish the plugin and preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing only and is not a security review

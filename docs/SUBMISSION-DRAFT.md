<!--
Marketplace submission for https://plugins.omarchy.org — UNSUBMITTED DRAFT.
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

Load, temperature and clock in the bar; in the panel a load graph, a bar per
hardware thread, every CPU temperature sensor the kernel exposes, memory, load
average and the busiest processes. Middle-click opens btop.

Process CPU can be shown as a share of the whole chip (everything at full tilt
sums to 100%) or per core, the `top` convention where one busy thread reads
100%. The maximum shown adapts to the machine's thread count.

Everything comes from `/proc` and `/sys`. Two standard-library Python scripts
in `bin/`, one importing the other in-process so a poll costs a single
interpreter start. No daemon, no root, no network, no external binaries. The
only writes outside the plugin folder are a lock and a sample-state file in
`$XDG_RUNTIME_DIR`, so removal is clean.

Package power is optional and off by default. It is read from the kernel's
RAPL energy counter, which most kernels ship root-only as the mitigation for
CVE-2020-8694; without access the plugin shows no power at all rather than
estimating, and never asks for elevated privileges. The README documents the
one udev rule that grants it, what that trades away, and how to undo it.

One of a trio with omarchy-gpu and omarchy-bandwidth, which share the same
panel layout and controls.

### Submission checklist

- [x] The repository is public and includes install and removal instructions
- [x] The license and any external dependencies are documented
- [x] I own or have permission to publish the plugin and preview assets
- [x] The plugin does not overwrite user configuration without explicit consent
- [x] I understand approval is for listing only and is not a security review

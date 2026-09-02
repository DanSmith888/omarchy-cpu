<!-- Human development notes. Deliberately not named CLAUDE.md or AGENTS.md:
     this file ships inside the installed plugin tree, and a coding agent that
     wandered in should read it as documentation, never as instructions. -->

# Developing this plugin

CPU load, temperature and clock in the Omarchy bar

Read the `omarchy-plugin-dev` skill first; it holds the conventions. This
file holds only what is specific to this repo.

## Identity

- id / IPC target / `moduleName`: `dansmith888.cpu`
- repo: `https://github.com/DanSmith888/omarchy-cpu.git`
- installed copy: `~/.config/omarchy/plugins/dansmith888.cpu`
- kind: `bar-widget`, entry point `BarWidget.qml`

## Map

- `manifest.json` — the contract; bump `version` on release.
- `BarWidget.qml` — entry point. Owns the pill and the single IpcHandler; forwards open/close/opened to Panel.qml, which owns all state.
- `Model.js` — pure formatting/colour helpers; testable with plain node.
- `Sparkline.qml` — Canvas line graph used for the load history.
- `Panel.qml` — all state and the whole popup.
- `bin/cpustatus` — one JSON line for the QML; `{}` = nothing to show.
- `bin/cpuctl` — CLI: `get [--json]`, `doctor`, action verbs. Holds
  `PLUGIN_ID` / `REPO_URL` (keep in sync with the manifest).
- `docs/SUBMISSION-DRAFT.md` — marketplace issue body (unsubmitted).

## Dev loop

```bash
omarchy plugin validate . && ~/.claude/skills/omarchy-plugin-dev/scripts/lint.sh
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/dansmith888.cpu/
omarchy-shell shell toggle dansmith888.cpu '{}'
qs log -p "$OMARCHY_PATH/shell" --tail 100
bin/cpuctl doctor
```

## Rules

- Keep in sync on release: `manifest.version`, git tag `vX.Y.Z`,
  `moduleName` in every QML, `PLUGIN_ID`/`REPO_URL` in `bin/cpuctl`,
  README commands.
- stdlib Python only in `bin/`; no root, no network; locks in
  `$XDG_RUNTIME_DIR`.
- Never edit `/usr/share/omarchy/**`.
- No `git push`, tag push, or marketplace submission unless Daniel says so.

## Gotchas

- `cpustatus` imports `cpuctl` in-process (SourceFileLoader) so a poll is
  one Python start-up, not two. Keep `cpuctl.get()` import-safe.
- Load is a delta: the previous sample lives in
  `$XDG_RUNTIME_DIR/dansmith888.cpu.state.json`, guarded by the sibling
  `.lock`. A sample older than 60 s is discarded and a fresh 0.25 s pair
  is taken instead, so the first poll still returns a rate.
- Process CPU% is a share of one core (top(1) convention), so it can
  exceed 100.
- qmllint reports "unqualified access" for `root.`/`column.` references
  inside inline `component`s and `Component {}` blocks. Those are expected;
  only `Error:` lines matter.
- Temperature labels vary by driver: AMD gives Tctl/Tccd1/Tccd2, Intel
  gives "Package id 0". `Model.pickTemp` prefers the package sensor.

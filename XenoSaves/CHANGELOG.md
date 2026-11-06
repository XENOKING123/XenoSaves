# Changelog

All notable changes to XenoSaves. Dates are when the build was prepared.

## 0.3.14 — 2026-11-06
- **Share a save with review.** Members submit a PS5 save; an owner/admin tests it and
  approves or declines it before it is published. Private upload, server-enforced rules.
- **Security hardening.** Electron fuses + asar integrity: a modified app refuses to run.
  Run-as-node, debugger-inject and NODE_OPTIONS routes closed. Verified in the packaged exe.
- A reviewed save can only be published as the exact bytes that were tested (hash-pinned),
  and a withdrawn submission's ID can never be reused to slip in unreviewed content.

## 0.3.13 — 2026-11-06
- **Advanced Mode** rebuilt as a real hex-editor workbench: edit bytes, go-to offset, undo;
  find hex/text/number; before/after compare; value finder; Save Wizard quick codes (apply
  and make); smart scan for money/health/stats/unlocks; optional AI helper. Originals are
  never changed — edits save to a copy.

## 0.3.12 and earlier
- Grab saves from a stock PS5 (verified on hardware), community save collection, PS4 save
  index, cheats browser, My PSN, Save Library, themes, auto-update.

*(Full history lives in the application repository.)*

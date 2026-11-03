# Changelog

## 0.1.0 — 2026-11-02

First public preview of the one-click Windows installer.

- `Setup.cmd` / `setup.ps1`: prerequisite checks with explained, opt-in winget installs (Python 3.12, Node.js LTS,
  Docker Desktop or PostgreSQL 16), per-user install, generated access tokens, one-time hidden OpenAI key entry,
  Docker (recommended) or Native Workbench, Start Menu shortcuts and a drag-and-drop *Verify a Document* shortcut,
  `-DryRun` / `-SimulateMissing` preview.
- `Uninstall.cmd` / `uninstall.ps1`: removes only what Setup created; data deletion only after explicit confirmation.
- Bundles: Research Verification Workbench 0.1.0, Document Verification 0.1.0 (Workbench token support), Context
  Forge 0.1.0 (Windows PowerShell 5.1 install fixes), Get Files 0.1.0 (opt-in Docker host access, PowerShell 5.1
  install fix).

## 0.1.0 (license) — 2026-11-02

- Licensed under the PolyForm Noncommercial License 1.0.0 instead of Apache-2.0. Noncommercial use is free;
  commercial use requires a license from Brightline IP.

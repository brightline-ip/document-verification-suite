# Changelog

## 0.1.0 (honest reports) — 2026-11-06

- Bundles the Research Verification Workbench with its status changes (migration 016, applied on repair), Document
  Verification with reports that separate findings from claims nothing was compared with, Context Forge 0.1.1 and the
  latest Get Files.
- *Verify a Document* states plainly when nothing was compared and exits 3; it counts findings and not-compared
  statements separately, shows the reason, evidence gaps and coverage, and says what the web search costs.
- README and SECURITY corrected: what each result means, library documents are not evidence, results follow Word headings
  only, the 10 is model calls and the searches inside them are not capped.
- Setup prefers Python 3.12 and offers it when another version is found; it no longer says a newer version will work. Repair
  mirrors program files, so stale files go, refuses a non-empty folder it did not create, and limits `-InstallRoot` to 62
  characters. README: do not run a bundled tool's own `Setup.cmd`.

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

## 0.1.0 (security review fixes) — 2026-11-02

- Secret files (Workbench settings with the OpenAI key, tokens, database password) are restricted to your account
  before the secret is written; Setup refuses FAT/exFAT install drives and paths containing `%`, `!` or `"`.
- Access lists are granted by account SID.
- Uninstall unlinks junctions and symbolic links instead of following them.
- Docker Compose detection no longer fails on a Docker stderr notice under Windows PowerShell 5.1.
- SECURITY.md: secrets are also in the Docker containers' environment. README: repair rewrites the Workbench `.env`.

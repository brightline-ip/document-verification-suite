# Security

## Supported versions

Only the 0.1.x public preview.

## Reporting a vulnerability

Use GitHub's private security advisory feature on this repository (or on the repository of the bundled tool
concerned). Do not open a public issue for a vulnerability, and do not include real client documents, API keys or
tokens in a report.

## What the installer does with your computer

- Installs per user, into `%LOCALAPPDATA%\Brightline\DocVerify` by default. No Windows service, scheduled task,
  registry Run key, firewall rule or system setting is created or changed.
- Starts PowerShell with `-ExecutionPolicy Bypass` for its own scripts only; the machine and user execution policies
  are not changed. The scripts are not code-signed: verify the release zip's SHA-256 checksum before running it.
- Clears the "downloaded from the Internet" mark (Zone.Identifier) on the script and program files it copies into
  the install folder, so the shortcuts run without repeated warnings. It does not touch any other file.
- Offers third-party programs through Windows Package Manager (`winget`) only after an explicit "Y", with the exact
  command shown first. It never uninstalls or upgrades them.
- Uninstall removes only what Setup recorded: its shortcuts, its install folder (identified by a marker file), and
  in Docker mode its own Compose project, image and, only if you confirm deleting data, its volumes. It refuses to
  delete a folder without the marker.

## What the suite trusts

- **Single user, local only.** All four services listen on `127.0.0.1` (the Workbench container's port is published
  on `127.0.0.1` only; its database has no published port). Anyone who can log in as you can use them and spend your
  OpenAI budget.
- **Secrets on disk, readable by your account only** (explicit access lists, no inheritance): the Workbench `.env`
  file (your OpenAI key, database password, tokens), the Workbench access token, the Get Files token, the stored
  database password. Context Forge's token also allows SYSTEM and Administrators, as that tool's own installer
  sets it. Each secret file is restricted before the secret is written; Setup refuses FAT/exFAT install drives,
  which cannot be restricted. In Docker mode the same values are also in the Workbench containers' environment,
  so anything running as you can read them with `docker inspect` or Docker Desktop.
- **Workbench access token.** Required on every Workbench API call. *Open Research Workbench* copies it to the
  clipboard so it can be pasted into the page; clipboard history (Win+V) and clipboard sync, if you enabled them,
  may keep a copy.
- **Docker access to Get Files.** In Docker mode, Get Files is started with `GET_FILES_ALLOW_DOCKER_HOST=1`, so the
  Workbench container can call it as `host.docker.internal`. The Get Files token is still required.
- **Documents and sources are untrusted data.** They are sent to the model marked as data, with an instruction not to
  follow instructions inside them. That lowers the risk; model output can still be wrong or manipulated. Read the quoted
  passages.
- **Process control.** Stop and uninstall end only processes whose command line or recorded process ID belongs to
  this installation. They never stop other copies of these tools or other programs on the same ports.

## Local-only data statement

Your documents, reports, source library, Workbench database and all credentials stay on your computer, and the text
you verify stays there until you delete it (see the README, "What stays behind"). Data leaves
it only when you verify a document (text and source passages go to OpenAI, including passages from a source folder you
choose, a copy of which stays in the local Get Files library until you remove it), when the Workbench searches the web and
downloads public sources, and when Setup downloads packages and Docker images. See DISCLAIMER.md.

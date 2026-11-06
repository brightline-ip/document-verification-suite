# Brightline Document Verification Suite

**Public preview 0.1.0** · Windows 10/11 · PolyForm Noncommercial 1.0.0 · Brightline IP

A one-click Windows installer for having a model check the factual and legal statements in your Word and PDF drafts
against sources it finds on the web. Drop a `.docx`, `.pdf` or `.pptx` on the **Verify a Document** shortcut and, a few minutes
later, a report opens in your browser. It separates the statements a model compared with a source and found a problem
with, with the quoted passage; the statements where nothing was compared, and why; and the statements a model verified.
If no usable source turned up, the first line of the report says that nothing was compared.

It is a research aid for patent and legal practitioners, not legal advice. Read [DISCLAIMER.md](DISCLAIMER.md).

> **Before you start, two things you must accept:**
>
> - **Cost.** Every verification makes paid calls to the OpenAI API with **your own API key**, billed to your
>   OpenAI account. The cost grows with the length of the document and with web searching for sources. The suite
>   caps the number of calls per day, but that is not a dollar cap: set a monthly budget in your OpenAI account.
> - **Confidentiality.** The text of each document you verify, and passages from its sources, are sent to OpenAI.
>   Do not verify privileged, confidential, client or export-controlled material unless your professional
>   obligations, your client's consent and OpenAI's terms allow it.

## What you get

| Tool | What it does for you |
|---|---|
| **Research Verification Workbench** | The engine. Finds the checkable statements in your text, gathers sources, compares each statement with quoted source passages and writes the findings. Also has its own web page for deeper work (projects, sources, fix-up drafts, exports). |
| **Document Verification** (`docverify`) | Takes your Word or PDF file, sends its text to the Workbench and writes the report. Results are listed under your Word headings; a PDF carries no heading information, so its results are not sorted by section. |
| **Context Forge** | Pulls text out of PDFs, including scanned pages (Windows' built-in OCR), when the Workbench cannot read a PDF itself. |
| **Get Files** | Your local library of source documents (decisions, statutes, articles). A document from it can be linked to a statement, but a linked document is **not** used as evidence: nobody has classed it, so those statements read `NO_ELIGIBLE_SOURCE`. A document added from a local file cannot be linked at all, because it has no source address (the report lists this). When the web search runs, a stored document may be reused as a secondary source, which counts only for a statement that does not need a primary one. |

Setup installs all four for your Windows account only, connects them to each other with private access tokens, and
adds these shortcuts:

- Start Menu, folder **Brightline Verification Suite**: *Start Brightline Verification Suite*, *Stop Brightline
  Verification Suite*, *Open Research Workbench*, *Verify a Document* (opens a file picker), *Uninstall Brightline
  Verification Suite*.
- Desktop: **Verify a Document**. Drag a `.docx`, `.pdf` or `.pptx` file onto it. (Start Menu entries cannot receive dragged
  files, which is why this one is on the Desktop.)

## Requirements

- **Windows 11 or Windows 10** (64-bit, version 22H2 recommended), Home or Pro.
- About **6 GB of free disk space** and 8 GB of memory (16 GB is more comfortable with Docker Desktop).
- **Internet access** during installation (Python packages, Docker images) and for every verification (OpenAI).
- **An OpenAI account with API billing set up**, and an API key from <https://platform.openai.com/api-keys>.
  An API key is not the same as a ChatGPT subscription: API use is billed separately.
- The ability to approve installations on your computer (Windows may show "Do you want to allow this app to make
  changes?" while Python or Docker Desktop is installed).

Setup checks for the programs below and, if one is missing, explains why it is needed and offers to install it with
Windows Package Manager (`winget`). Nothing is installed unless you type **Y**.

| Program | Why | Installed with | Cost |
|---|---|---|---|
| Python 3.12 | Runs Document Verification, Context Forge and Get Files | `winget install --id Python.Python.3.12 --exact --source winget --accept-source-agreements --accept-package-agreements` | Free |
| Docker Desktop | Runs the Workbench and its database (recommended mode) | `winget install --id Docker.DockerDesktop --exact --source winget --accept-source-agreements --accept-package-agreements` | Free for most practitioners, see below |
| Node.js LTS | Optional in Docker mode (connectors for AI assistants); required in Native mode | `winget install --id OpenJS.NodeJS.LTS --exact --source winget --accept-source-agreements --accept-package-agreements` | Free |
| PostgreSQL 16 | Native mode only | `winget install --id PostgreSQL.PostgreSQL.16 --exact --source winget --interactive --accept-source-agreements --accept-package-agreements` | Free |

Setup never uninstalls or upgrades these programs.

### Why Docker Desktop is the recommended path

The Workbench needs a PostgreSQL database and a Python runtime for Word/PDF/Excel reports. With **Docker Desktop**
all of that comes as one sealed, pre-tested package: Setup creates the database with a random password, nothing
listens on your network (only on `127.0.0.1`), and there is no database server to install, configure, patch or
give an administrator password to. Updating or removing the suite is one command each. On a Windows 11 Home laptop
this has the fewest steps that can go wrong. Its downsides: a large first download (about 500 MB), Windows
virtualization (WSL 2) must be available, and Docker Desktop must be running when you verify (the Start shortcut
starts it for you).

The **Native** path (`-WorkbenchMode Native`) runs the Workbench directly with Node.js and a PostgreSQL server you
install yourself. It uses only free software, but the PostgreSQL installer asks you to choose an administrator
password, runs a database service permanently, and the Word/PDF report packages are installed from PyPI without the
hash-pinning the Docker image has. Use it if Docker Desktop's licence does not fit your organisation or your computer
cannot run WSL 2.

**Docker Desktop licence.** Docker Desktop is free for personal use, education, non-commercial open-source projects
and **businesses with fewer than 250 employees and less than USD 10 million annual revenue**. Larger organisations
need a paid Docker subscription
([terms](https://www.docker.com/legal/docker-subscription-service-agreement/)); use Native mode instead. The suite
never requires a paid product.

## Install

1. **Download** `brightline-docverify-suite-0.1.0.zip` and `SHA256SUMS.txt` from the GitHub release page.
2. **Check the download is genuine.** The zip and its scripts are not code-signed, so Windows cannot vouch for
   them; the published SHA-256 checksum is how you confirm the file was not altered. Open PowerShell (Start menu,
   type *PowerShell*) and run, adjusting the folder:

   ```powershell
   Get-FileHash "$env:USERPROFILE\Downloads\brightline-docverify-suite-0.1.0.zip" -Algorithm SHA256
   ```

   The `Hash` shown must equal the value next to `brightline-docverify-suite-0.1.0.zip` in `SHA256SUMS.txt` (and in
   the release notes), ignoring upper/lower case. If it differs, delete the file and do not run it.
3. **Extract** the zip: right-click it, **Extract All...**, **Extract**. Do not run Setup from inside the zip
   window. Open the extracted folder `brightline-docverify-suite-0.1.0`.
4. **Double-click `Setup.cmd`.** What Windows may show, and what to do:
   - *"Windows protected your PC"* (Microsoft Defender SmartScreen, because the file came from the internet and is
     unsigned): click **More info**, then **Run anyway**. Do this only if the checksum in step 2 matched.
   - *"Open File - Security Warning ... The publisher could not be verified"*: click **Run**.
   - A black window opens and Setup talks you through the rest. Setup starts PowerShell with
     `-ExecutionPolicy Bypass` for itself only; it does not change your computer's PowerShell policy.
   - *"Do you want to allow this app to make changes to your device?"* appears only if you agree to install Python,
     Docker Desktop or another program: choose **Yes**.
5. **Answer Setup's questions.** It checks your computer, offers any missing programs, asks you to confirm the cost
   and confidentiality notes, and asks once for your OpenAI API key. Paste it (right-click or Ctrl+V) and press
   Enter; the key is not shown on screen.
6. **If Setup installed Docker Desktop**, it stops there on purpose: restart Windows if asked, open *Docker
   Desktop* from the Start menu, accept its terms, wait until it shows **Engine running**, then double-click
   `Setup.cmd` again.
7. Setup copies the tools to `%LOCALAPPDATA%\Brightline\DocVerify`, installs their Python packages, builds and
   starts the Workbench (first time 5-15 minutes), creates the shortcuts and finally checks that every part can
   reach every other. It ends with *"Setup finished. Everything is running."*

You can delete the downloaded zip and extracted folder afterwards; everything needed is in the install folder.

**Do not also run the `Setup.cmd` of a bundled tool** (for example under `tools\context-forge`, or in the install
folder's `app\` copy). This installer sets up those tools and connects them to each other. A tool's own Setup installs
a separate copy, with its own token and on the same port.

## Your first verification

1. Make a test copy of a non-confidential draft (Word `.docx` or a text-based PDF).
2. Drag it onto **Verify a Document** on your Desktop (or use Start Menu > Brightline Verification Suite > Verify
   a Document and pick the file).
3. The window shows the file name and reminds you that the text goes to OpenAI and is billed to you. Type **Y** and
   press Enter.
4. Progress lines appear: importing the document, saving it as a Workbench version, *Extracting claims (paid OpenAI
   call)*, *Searching for sources (paid OpenAI and web search calls)*, *Verifying claims against sources (paid
   OpenAI call)*. A short memo takes a few minutes; a long brief can take 30 minutes. Keep the window open.
5. When it finishes, the window says what the run established, for example *"23 statements found: 15 compared with a
   source, 6 not compared, 2 needing no source"*, and your browser opens the report.

**Nothing compared.** If no statement reached a source, the window and the top of the report say: *"No claim was compared
with any source; this report says nothing about whether the statements are right."* That is a gap in the check, not a
finding about your draft.

What the results mean when a model did compare a statement with passages:

| Result | Meaning |
|---|---|
| VERIFIED | A model judged that a quoted source passage supports the statement. The quote is checked to appear in the source; the judgement is not |
| OVERSTATED | A model judged that the source supports only a weaker or narrower version |
| MISCITED | A model judged that the cited source or pin cite does not say this. Code also sets it when a quotation of 5 or more words is in none of the sources, and says so in the report |
| CONTRADICTED | A model judged that a source says the opposite |
| STALE | A model's label for an outdated source. No date check backs it |
| UNSUPPORTED | A model did not find it in the passages it was shown. Those are the closest passages, not the whole source |
| UNVERIFIABLE | A model could not decide from those passages |
| FABRICATED | A model's label. No citation lookup backs it, so check it by hand |

Why nothing was compared for a statement (the report shows this as **Not compared**, and these are not findings):

| Reason | Meaning |
|---|---|
| NO_SOURCES | No source was linked to it |
| NO_ELIGIBLE_SOURCE | Sources were linked, but none qualifies as evidence. Library documents do not, and a statement that needs a primary source cannot use a secondary one |
| SOURCES_UNAVAILABLE | A source was found but could not be read: a failed download, blocked, a suspected login page or no usable text |
| NO_MATCHING_PASSAGE | No passage in the sources shared a word with the statement |
| INVALID_MODEL_REPLY | Passages were sent, but the model's reply failed validation, so there is no verdict |

NOT_APPLICABLE means a model marked the statement as needing no outside source. It was not checked against anything.

Every verdict is a model's reading, and whether a source counts as PRIMARY is usually a model's label too; the report says
who assigned it. Read the quoted passages before relying on any result. The report also shows whether the model said it went
through the whole text.

Reports are saved under `%LOCALAPPDATA%\Brightline\DocVerify\data\docverify\projects\<id>\reports\`. For section
selection (Word heading styles, or block numbers for a PDF), corrected drafts and Word/PDF exports, use the `docverify` command line (see the Document Verification
README in `app\document-verification`) or the Workbench web page (**Open Research Workbench**; the first time in each
browser session it asks for an access token, which the shortcut has already put on your clipboard: click the box,
press Ctrl+V, confirm).

## Everyday use

- **After restarting Windows**, run **Start Brightline Verification Suite** (Verify a Document also starts anything
  that is not running). In Docker mode it starts Docker Desktop if needed.
- **Stop Brightline Verification Suite** stops the four services. Your documents and settings are kept.
- **Change the OpenAI key**: run `Setup.cmd` again (from the extracted folder) and answer **N** to "Keep it?".
  Re-running Setup also repairs an installation and keeps your data: it mirrors the program files from the download,
  so files an older version left behind are removed, and it applies the Workbench's database updates. It rewrites the
  Workbench settings file (`app\research-workbench\.env`), so make any manual changes there again afterwards.

## Costs

The suite itself is free. You pay OpenAI for model use under your own account
([pricing](https://openai.com/api/pricing/)). What drives cost: document length, the number of statements, and
source searching. The Verify shortcut lets the Workbench search, because with no sources nothing can be compared. That
adds up to 10 model calls per document, one per group of related statements, and each can run several web searches.
**The searches inside a call are not capped**, so 10 limits model calls, not searches or money. One more call is made
for each statement that has a usable source passage. The Workbench refuses new model calls after 500 calls or 32 MB of
text per day (UTC) and after 400 calls per run; these limit volume, not money. Set a monthly budget at
<https://platform.openai.com/settings/organization/limits>.

## Privacy and security

- **Stays on your computer**: your original files, the reports, the source library, the Workbench database, all
  tokens and your API key. All four services listen on `127.0.0.1` only and cannot be reached from your network.
- **Leaves your computer**: the document text and source passages sent to OpenAI for each verification; web
  searches and downloads of public source pages the Workbench chooses; package downloads during Setup.
- **Secrets**: your OpenAI key is stored only in `app\research-workbench\.env` inside the install folder. That file,
  the Workbench access token (`secrets\`) and the service tokens of Context Forge and Get Files are readable by your
  Windows account only. The Workbench access token protects its web page and API against other programs and users on
  the same computer. *Open Research Workbench* copies it to your clipboard so you can paste it.
- **What stays behind**: the text you verify stays in the Workbench database and in Document Verification's data folder
  (including `journal.sqlite3`) until you delete it. *Uninstall*, choosing to delete your data, removes all of it. To delete one
  document, see "What stays behind" in the Document Verification README (`app\document-verification`). Files you chose as a source folder also stay in the Get Files library, which has no way to remove one document; only *Uninstall* with data deletion removes them. With Docker, run
  the Workbench's delete command from `app\research-workbench` with this suite's project name:
  `docker compose -p brightline-docverify exec app node scripts/delete-project.js <workbench-project-id> --yes`
  (add `-T` after `exec` if you run it from a script rather than a terminal).
- **What it trusts**: single-user computer. Anyone who can log in as you can use the suite and spend your OpenAI
  budget. See [SECURITY.md](SECURITY.md).

## Advanced settings

Run Setup from PowerShell to change defaults, for example
`powershell -ExecutionPolicy Bypass -File .\setup.ps1 -WorkbenchPort 13080`.

| Parameter | Default | Purpose |
|---|---|---|
| `-InstallRoot` | `%LOCALAPPDATA%\Brightline\DocVerify` | Install folder, at most 62 characters. A non-empty folder Setup did not create is refused |
| `-WorkbenchMode` | `Docker` | `Docker` or `Native` |
| `-WorkbenchPort` / `-DocVerifyPort` / `-ContextForgePort` / `-GetFilesPort` | `3080` / `3091` / `8765` / `8766` | Local ports (change them if another program already uses one) |
| `-ComposeProject` | `brightline-docverify` | Docker Compose project name (containers and volumes are prefixed with it) |
| `-PythonExe` | auto (3.12 preferred; if another version is found, Setup offers 3.12) | Python interpreter to use |
| `-DocumentsFolder` | your Documents folder | Folder the Document Verification HTTP API and Context Forge may read |
| `-ContextForgeInputRoots` | data folder + Documents | Folders Context Forge may read |
| `-PostgresHost` / `-PostgresPort` / `-PostgresAdminUser` | `127.0.0.1` / `5432` / `postgres` | Native mode database server |
| `-ShortcutFolder` / `-DesktopFolder` / `-NoDesktopShortcut` | Start Menu folder / Desktop | Where shortcuts go |
| `-DryRun` | off | Check prerequisites and show what Setup would do, including winget commands, without changing anything |
| `-SimulateMissing Python,Node,Docker,PostgreSQL` | none | With `-DryRun`: preview the installation offers as if those programs were missing |
| `-NoStart` | off | Install without starting the services |

Install folder layout: `app\` (the four tools), `bin\` (shortcut scripts), `config\` (`suite.json`,
`docverify.json`), `secrets\`, `data\` (your documents, reports, source library), `logs\`.

## Troubleshooting

| Symptom | What to do |
|---|---|
| Setup says a port is already used | Another program (perhaps a separate copy of one of these tools) uses it. Stop it, or re-run Setup with another port (see Advanced settings). |
| "Docker Desktop did not start" | Open Docker Desktop from the Start menu and wait for *Engine running*. If it asks to update WSL or to enable virtualization, follow its instructions (virtualization may have to be enabled in your PC's firmware settings). |
| "OpenAI rejected the API key" | Create a new key at <https://platform.openai.com/api-keys> and run Setup again to replace it. |
| "OpenAI refused the request because of a usage limit" | Usually no credit or billing on the OpenAI account, or too many requests at once. Check <https://platform.openai.com/settings/organization/billing>. |
| "The Workbench could not reach OpenAI" | Check the internet connection, VPN or firewall; `api.openai.com` must be reachable. |
| "This PDF has no readable text layer" | The PDF is scanned and OCR could not read every page. Use the Word original or a text-based PDF. OCR needs the Windows English language pack (Settings > Time & language). |
| "No claim was compared with any source", or many statements are *Not compared* | Look at the reason shown for each. Most often the web search found nothing usable, or the sources could not be read. To check against your own files, answer Y when *Verify a Document* asks for a folder of source material. Adding documents to the Get Files library does not by itself change this, because a linked document is not used as evidence; only a web search run can reuse a stored document, and the report then names it. Running the shortcut again repeats the search and is billed again. |
| "The Workbench found no checkable claims" | The model found no statement to check, so nothing was compared and no report was written. |
| The Workbench page asks for an access token | Use *Open Research Workbench* (it copies the token), click the box, press Ctrl+V. |
| Something else | Logs are in `%LOCALAPPDATA%\Brightline\DocVerify\logs`. Run *Start Brightline Verification Suite* to see which part does not start. |

## Uninstall

Start Menu > Brightline Verification Suite > **Uninstall Brightline Verification Suite** (or `Uninstall.cmd` in the
extracted folder). It asks whether to also delete your data (verification projects, reports, source library and the
Workbench database); the default keeps it so a later reinstall finds it again. It removes only what Setup created:
the shortcuts, the install folder, and in Docker mode the suite's containers, its image and (only if you chose to
delete data) its volumes. Python, Node.js, Docker Desktop and PostgreSQL stay installed; remove them in Windows
Settings > Apps if you no longer need them. Revoke your OpenAI API key if you no longer use it.

## Limitations

- Public preview. This installer was tested on one Windows 11 computer that already had the prerequisites; the
  winget installation offers were exercised only in `-DryRun`. Windows 10, a clean computer and Native mode on a
  real PostgreSQL installation have not been verified by the publisher.
- One end-to-end run with a real OpenAI key was made, on a short synthetic memo and an earlier build. It does not measure accuracy, and source folders and the word-for-word quotation check have been tested only with a simulated provider unless the release notes say otherwise.
- Old `.doc` files are not accepted (save them as `.docx`). Image-only PDF pages depend on Windows OCR.
- Python: the bundled Context Forge and Get Files tests ran on Python 3.12 and Document Verification's on 3.12 and 3.14. The
  full installer has not been run by the publisher on a computer with only Python 3.12.
- Single-user, local only. Not a server for a team.

## License and disclaimer

PolyForm Noncommercial License 1.0.0: free for noncommercial use (personal, research, education, nonprofit). Commercial use (including use by or for a law firm, company or paying client) requires a separate license from Brightline IP: contact timisbright@gmail.com.
The installer, the Research Verification Workbench and Document Verification are under this license; Context Forge
and Get Files are Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The four bundled tools carry their own LICENSE,
README and SECURITY files under `tools\`. Not legal advice: [DISCLAIMER.md](DISCLAIMER.md).

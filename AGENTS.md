# Agent notes for apple-books-external-mount

Before diagnosing anything here, read `docs/RUNBOOK.md` — it has the known
failure modes and their verified fixes. Do not re-derive them. Quick map:

| Symptom | Known fix (RUNBOOK section) |
|---|---|
| Books.app shows only cloud books / collections say "No Books" | Catalog pruned because Books ran without the media. `./scripts/apple-books-external-mount.sh restore-catalog` (auto-heals on next mount). *Catalog protection* |
| Finder → iPhone has no Audiobooks/Books/Podcasts tabs | **Reboot the Mac.** Daemon restarts, Finder restart, iPhone reboot, quitting Books do not work. *If Finder loses the … tabs* |
| Agent log: `mount failed` / `cannot attach image` right after plugging in | Transient; agent retries after 120s. If persistent, `fsck_apfs -n` the image volume. *First attach after plugging in can fail transiently* |
| `status` says `sha1 folders visible: 0` but Books works | False reading from a shell without access to the agent-mounted volume. Trust the agent log. *Reading `status` when the agent did the mounting* |
| `rm`/`mount_apfs`: Operation not permitted from launchd | `bin/abe-launcher` needs Full Disk Access. *LaunchAgent needs Full Disk Access* |
| `launchd` job hangs silently accessing `/Volumes/25External` | Non-FDA `launchd` child blocked on invisible `tccd` Removable Volumes prompt. Route through `bin/abe-launcher` (`snapshot-catalog` / `finisher-books-sync`) or grant FDA to the Mach-O launcher. *Companion intake & tracker hooks* |
| Duplicate ` 1.m4b` in `sha1-*` folder or duplicate collection rows | Orphan `sha1-*` dir from prior interrupted import, or `ZBKCOLLECTIONMEMBER` edited without `SELECT`-first + `Z_PRIMARYKEY.Z_MAX` bump. *Companion intake & tracker hooks* |
| iPhone lost its audiobooks after charging from the Mac | Finder auto-sync ran against an empty library. Keep "Automatically sync when this iPhone is connected" **off**. *Finder sync can wipe the phone* |

Operational rules:

- Never open Books.app while `25External` is unplugged — it prunes the catalog
  within seconds. The agent guard quits it, but not fast enough to prevent it.
- Shells sandboxed by the editor cannot read the Books containers (reads hang),
  and non-FDA `launchd` jobs touching `/Volumes/25External` can hang silently on
  an invisible `tccd` Removable Volumes prompt instead of returning `EPERM`.
  Run privileged script commands through `bin/abe-launcher` with a one-shot
  launchd plist (recipe in RUNBOOK), never `launchctl submit` (it loops).
- Never overwrite or temporarily swap `scripts/apple-books-external-mount.sh`
  to piggyback on `bin/abe-launcher` Full Disk Access (can cause **Eject Books
  Drive** to false-greenlight safe unplug while still mounted). Use the
  first-class `snapshot-catalog` and `finisher-books-sync` subcommands.
- Companion intake daemon & dashboard live in
  `~/Library/Application Support/audiobook-tracker/` (`audiobook_ops`,
  `http://127.0.0.1:8765/`, `AGENTS.md` in that directory). When editing
  `BKLibrary-*.sqlite` via `finisher-books-sync`, `Books.app` must be closed
  with no iPhone sync active, `ZBKCOLLECTIONMEMBER` requires `SELECT` before
  `INSERT` with both `ZASSET` and `ZASSETID` populated (including
  `Want_To_Read_Collection_ID`), `Z_PRIMARYKEY.Z_MAX` (`Z_ENT=2,3`) must be
  bumped, and `Books.app` must not be relaunched afterward.
- Eject with the Desktop **Eject Books Drive** app or `… eject`, never Finder's ⏏.

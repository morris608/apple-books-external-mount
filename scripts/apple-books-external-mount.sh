#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/config/apple-books-external-mount.env"

mkdir -p "${ABE_LOG_DIR}"
LOG="${ABE_LOG_DIR}/apple-books-external-mount.log"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  print -- "$msg" | tee -a "$LOG" >/dev/null
  print -- "$msg"
}

notify() {
  # Disabled: osascript notifications nested under Eject Books Drive.app
  # caused AppleEvent timed out (-1712). Logging only.
  log "notify: $1 — $2"
}

inhibit_mount() {
  # Prevent LaunchAgent ensure from remounting during/after eject.
  local seconds="${1:-120}"
  local until=$(( $(date +%s) + seconds ))
  print -r -- "$until" >"${ABE_INHIBIT}"
}

mount_inhibited() {
  [[ -f "${ABE_INHIBIT}" ]] || return 1
  local until
  until="$(cat "${ABE_INHIBIT}" 2>/dev/null || print 0)"
  if [[ "$(date +%s)" -lt "${until}" ]]; then
    return 0
  fi
  rm -f "${ABE_INHIBIT}"
  return 1
}

have_lock() {
  if [[ -f "${ABE_LOCK}" ]]; then
    local oldpid
    oldpid="$(cat "${ABE_LOCK}" 2>/dev/null || true)"
    if [[ -n "${oldpid}" ]] && kill -0 "${oldpid}" 2>/dev/null; then
      return 0
    fi
    rm -f "${ABE_LOCK}"
  fi
  return 1
}

acquire_lock() {
  if have_lock; then
    log "another apple-books-external-mount run holds the lock; exiting"
    exit 0
  fi
  print -r -- $$ >"${ABE_LOCK}"
}

release_lock() {
  rm -f "${ABE_LOCK}"
}

external_mounted() {
  # Prefer the volume path — UUID alone can be true while /Volumes/25External is gone.
  [[ -d "/Volumes/${ABE_EXTERNAL_NAME}" ]]
}

audiobooks_is_mount() {
  /sbin/mount | /usr/bin/grep -F " on ${ABE_AUDIOBOOKS_PATH} " >/dev/null
}

quit_books() {
  # Prefer killall only — avoid nested osascript AppleEvents when invoked from
  # the Eject Books Drive.app (that caused AppleEvent timed out -1712).
  /usr/bin/killall Books 2>/dev/null || true
  /usr/bin/killall com.apple.BKAgentService 2>/dev/null || true
  sleep 2
  /usr/bin/killall -9 Books 2>/dev/null || true
  /usr/bin/killall -9 com.apple.BKAgentService 2>/dev/null || true
  # bookassetd serves the catalog to Finder sync and caches it; a stale copy
  # hid the Audiobooks tab after the 2026-08-07 restore. It respawns on demand.
  /usr/bin/killall bookassetd 2>/dev/null || true
  sleep 1
}

books_running() {
  /usr/bin/pgrep -x Books >/dev/null 2>&1 || /usr/bin/pgrep -x com.apple.BKAgentService >/dev/null 2>&1
}

guard_books() {
  # Books prunes its catalog (BKLibrary + Books.plist) when it runs while the
  # media is absent — happened 2026-08-07 and 2026-09-09. Quit it fast.
  (( ${ABE_GUARD_BOOKS:-1} )) || return 0
  audiobooks_is_mount && return 0
  if books_running; then
    log "GUARD: Books running without media mounted — quitting it to protect the catalog (mount ${ABE_EXTERNAL_NAME} first)"
    quit_books
  fi
}

catalog_path_count() {
  # Number of asset "path" entries in a Books.plist (2 per audiobook). 0 if unreadable.
  local plist="${1:-${ABE_BOOKS_PLIST}}" n=0
  if [[ -f "${plist}" ]]; then
    n="$(/usr/bin/plutil -convert xml1 -o - "${plist}" 2>/dev/null | /usr/bin/grep -c '<key>path</key>')" || n=0
  fi
  print -r -- "${n:-0}"
}

backup_catalog() {
  # Snapshot BKLibrary, BKSeries and Books.plist to the external drive. Call
  # with Books quit. Refuses to save a pruned catalog, and refuses to save one
  # noticeably smaller than the last good backup (partial prune).
  setopt LOCAL_OPTIONS NULL_GLOB
  local n last_n=0
  n="$(catalog_path_count)"
  if (( n < ABE_CATALOG_MIN_PATHS )); then
    log "catalog backup SKIPPED: Books.plist has ${n} path entries (< ${ABE_CATALOG_MIN_PATHS}) — looks pruned; run: $0 restore-catalog"
    return 0
  fi
  if [[ -f "${ABE_CATALOG_BACKUP_DIR}/latest/Books.plist" ]]; then
    last_n="$(catalog_path_count "${ABE_CATALOG_BACKUP_DIR}/latest/Books.plist")"
    if (( n * 10 < last_n * 9 )); then
      log "catalog backup SKIPPED: ${n} path entries vs ${last_n} in last backup — possible partial prune"
      return 0
    fi
  fi
  if ! external_mounted; then
    log "catalog backup skipped: ${ABE_EXTERNAL_NAME} absent"
    return 0
  fi
  local stamp="$(date '+%Y%m%dT%H%M%S')"
  local dest="${ABE_CATALOG_BACKUP_DIR}/${stamp}"
  mkdir -p "${dest}" || { log "catalog backup failed: cannot create ${dest}"; return 0; }
  cp "${ABE_BKLIBRARY_DIR}"/BKLibrary-*.sqlite* "${dest}/" 2>>"$LOG" || true
  cp "${ABE_BKSERIES_DIR}"/BKSeries-*.sqlite* "${dest}/" 2>>"$LOG" || true
  cp "${ABE_BOOKS_PLIST}" "${dest}/" 2>>"$LOG" || true
  local -a libs=("${dest}"/BKLibrary-*.sqlite)
  if [[ -f "${dest}/Books.plist" && ${#libs} -gt 0 ]]; then
    rm -f "${ABE_CATALOG_BACKUP_DIR}/latest"
    ln -s "${stamp}" "${ABE_CATALOG_BACKUP_DIR}/latest"
    log "catalog backed up: ${dest} (${n} path entries)"
    local -a old=("${ABE_CATALOG_BACKUP_DIR}"/2*(/N))
    while (( ${#old} > ABE_CATALOG_KEEP )); do
      rm -rf "${old[1]}"
      shift old
    done
  else
    log "catalog backup INCOMPLETE at ${dest} — check ${LOG}"
    rm -rf "${dest}"
  fi
}

restore_catalog_from() {
  # Replace the live catalogs with the copies in $1 (flat dir: BKLibrary-*.sqlite*,
  # BKSeries-*.sqlite*, Books.plist). Requires the media to be mounted, otherwise
  # Books would prune the restored catalog again on launch. Relaunches Books.
  setopt LOCAL_OPTIONS NULL_GLOB
  local src="$1" n
  [[ -f "${src}/Books.plist" ]] || { log "restore-catalog: no Books.plist in ${src}"; return 1; }
  n="$(catalog_path_count "${src}/Books.plist")"
  if (( n < ABE_CATALOG_MIN_PATHS )); then
    log "restore-catalog: source ${src} looks pruned (${n} path entries); refusing"
    return 1
  fi
  if ! audiobooks_is_mount; then
    log "restore-catalog: media not mounted at ${ABE_AUDIOBOOKS_PATH}; mount first"
    return 1
  fi
  quit_books
  local stamp="$(date '+%Y%m%dT%H%M%S')"
  local pruned="${ABE_CATALOG_BACKUP_DIR}/pruned-${stamp}"
  mkdir -p "${pruned}"
  cp "${ABE_BKLIBRARY_DIR}"/BKLibrary-*.sqlite* "${pruned}/" 2>/dev/null || true
  cp "${ABE_BKSERIES_DIR}"/BKSeries-*.sqlite* "${pruned}/" 2>/dev/null || true
  cp "${ABE_BOOKS_PLIST}" "${pruned}/" 2>/dev/null || true
  rm -f "${ABE_BKLIBRARY_DIR}"/BKLibrary-*.sqlite* "${ABE_BKSERIES_DIR}"/BKSeries-*.sqlite*
  cp "${src}"/BKLibrary-*.sqlite* "${ABE_BKLIBRARY_DIR}/" || { log "restore-catalog: BKLibrary copy failed"; return 1; }
  cp "${src}"/BKSeries-*.sqlite* "${ABE_BKSERIES_DIR}/" || { log "restore-catalog: BKSeries copy failed"; return 1; }
  cp "${src}/Books.plist" "${ABE_BOOKS_PLIST}" || { log "restore-catalog: Books.plist copy failed"; return 1; }
  log "catalog restored from ${src} (${n} path entries); pruned copy saved at ${pruned}"
  notify "apple-books-external-mount" "Books catalog restored (${n} entries)"
  /usr/bin/open -a Books 2>/dev/null || true
}

cmd_backup_catalog() {
  acquire_lock
  trap release_lock EXIT
  quit_books
  backup_catalog
}

cmd_restore_catalog() {
  acquire_lock
  trap release_lock EXIT
  local src="${1:-}"
  if [[ -z "${src}" ]]; then
    if [[ -f "${ABE_CATALOG_BACKUP_DIR}/latest/Books.plist" ]]; then
      src="${ABE_CATALOG_BACKUP_DIR}/latest"
    else
      src="${ABE_CATALOG_FALLBACK}"
      log "restore-catalog: no agent backup yet; using fallback ${src}"
    fi
  fi
  restore_catalog_from "${src}"
}

sweep_strays() {
  # Copy any sha1 folders that landed under the local Audiobooks dir while unmounted
  # onto the image volume (mounted temporarily at /Volumes) before bind-mounting.
  setopt LOCAL_OPTIONS NULL_GLOB
  local tmp_mount="/Volumes/${ABE_VOLUME_NAME}"
  if [[ ! -d "${ABE_AUDIOBOOKS_PATH}" ]]; then
    return 0
  fi
  if audiobooks_is_mount; then
    return 0
  fi
  # Ensure image volume is attached at default path for sweep destination
  if [[ ! -d "${tmp_mount}" ]]; then
    if [[ -d "${ABE_IMAGE}" ]]; then
      /usr/bin/hdiutil attach "${ABE_IMAGE}" >/dev/null
    fi
  fi
  if [[ ! -d "${tmp_mount}" ]]; then
    log "sweep skipped: volume not available at ${tmp_mount}"
    return 0
  fi
  local count=0
  local d
  for d in "${ABE_AUDIOBOOKS_PATH}"/sha1-*; do
    [[ -e "$d" ]] || continue
    local base
    base="$(basename "$d")"
    if [[ -e "${tmp_mount}/${base}" ]]; then
      log "sweep: ${base} already on volume; removing local stray"
      rm -rf "$d"
    else
      log "sweep: copying ${base} to volume"
      /usr/bin/ditto "$d" "${tmp_mount}/${base}"
      rm -rf "$d"
      count=$((count + 1))
    fi
  done
  log "sweep complete; moved ${count} stray folder(s)"
}

attach_image() {
  # Attach sparsebundle; prefer -nobrowse so Finder sidebar stays clean.
  if audiobooks_is_mount; then
    return 0
  fi
  if /sbin/mount | /usr/bin/grep -F "${ABE_VOLUME_NAME}" >/dev/null; then
    return 0
  fi
  if [[ ! -d "${ABE_IMAGE}" ]]; then
    log "image missing: ${ABE_IMAGE} (is ${ABE_EXTERNAL_NAME} mounted?)"
    return 1
  fi
  /usr/bin/hdiutil attach -nobrowse "${ABE_IMAGE}" >/dev/null
}

mount_at_audiobooks() {
  local dev
  dev="$(/usr/sbin/diskutil info "${ABE_VOLUME_NAME}" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')"
  if [[ -z "${dev}" ]]; then
    log "cannot find device node for ${ABE_VOLUME_NAME}"
    return 1
  fi
  # Drop default /Volumes mount if present, then mount hidden at Audiobooks path
  /usr/sbin/diskutil unmount "/Volumes/${ABE_VOLUME_NAME}" >/dev/null 2>&1 || true
  /sbin/mount_apfs -o nobrowse,nodev,nosuid "${dev}" "${ABE_AUDIOBOOKS_PATH}"
}

detach_image() {
  /usr/bin/hdiutil detach "${ABE_IMAGE}" -force >/dev/null 2>&1 || true
  # Fallback: detach by volume device if needed
  local dev
  dev="$(/usr/sbin/diskutil info "${ABE_VOLUME_NAME}" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')"
  if [[ -n "${dev}" ]]; then
    /usr/bin/hdiutil detach "${dev}" -force >/dev/null 2>&1 || true
  fi
}

mount_failed() {
  # Log, then back off so the LaunchAgent doesn't retry-loop — each retry
  # kills Books, which made the app unusable (2026-08-07 incident).
  local why="$1" secs="${2:-900}"
  log "mount failed: ${why}"
  log "backing off ${secs}s — recover manually: ./scripts/apple-books-external-mount.sh mount (from Terminal)"
  inhibit_mount "${secs}"
  notify "apple-books-external-mount" "Mount failed: ${why}"
  exit 1
}

cmd_status() {
  print "external: $(external_mounted && print mounted || print absent) (/Volumes/${ABE_EXTERNAL_NAME})"
  print "image: ${ABE_IMAGE}"
  print "image exists: $([[ -d ${ABE_IMAGE} ]] && print yes || print no)"
  print "audiobooks path: ${ABE_AUDIOBOOKS_PATH}"
  if audiobooks_is_mount; then
    print "audiobooks mount: YES"
    /sbin/mount | /usr/bin/grep -F " on ${ABE_AUDIOBOOKS_PATH} "
  else
    print "audiobooks mount: no"
  fi
  print -n "sha1 folders visible: "
  find "${ABE_AUDIOBOOKS_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'sha1-*' 2>/dev/null | wc -l | tr -d ' '
  print "aside present: $([[ -d ${ABE_ASIDE_PATH} ]] && print yes || print no)"
  if [[ -d "${ABE_ASIDE_PATH}" ]]; then
    print -n "aside sha1 folders: "
    find "${ABE_ASIDE_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'sha1-*' 2>/dev/null | wc -l | tr -d ' '
  fi
}

cmd_mount() {
  acquire_lock
  trap release_lock EXIT

  if ! external_mounted; then
    log "external drive not mounted; nothing to do"
    exit 0
  fi

  if audiobooks_is_mount; then
    log "already mounted at ${ABE_AUDIOBOOKS_PATH}"
    exit 0
  fi

  # Production cutover expects local tree already moved to aside.
  if [[ ! -d "${ABE_ASIDE_PATH}" ]]; then
    log "aside missing (${ABE_ASIDE_PATH}); refusing automatic cutover"
    notify "apple-books-external-mount" "Aside missing — mount aborted"
    exit 1
  fi

  # Attach before quitting Books — if the image can't attach there is no point
  # killing Books, and failing here must not leave Books dead every 30s.
  # Attach can fail transiently right after the drive appears (disk settling,
  # Time Machine starting on the same enclosure — 2026-09-09); Books has not
  # been quit yet, so a short retry is safe.
  attach_image || mount_failed "cannot attach image ${ABE_IMAGE}" 120

  quit_books
  sweep_strays

  if [[ ! -d "${ABE_AUDIOBOOKS_PATH}" ]]; then
    mkdir -p "${ABE_AUDIOBOOKS_PATH}" || mount_failed "cannot create mountpoint"
  elif [[ -n "$(ls -A "${ABE_AUDIOBOOKS_PATH}" 2>/dev/null)" ]]; then
    # Leftover strays would be shadowed by the mount. NB: this rm is denied
    # (TCC) when run from launchd — surface that instead of dying under set -e.
    rm -rf "${ABE_AUDIOBOOKS_PATH:?}"/* 2>>"$LOG" \
      || mount_failed "cannot clear mountpoint (TCC denies rm from launchd; run from Terminal)"
  fi

  # Unmount default /Volumes mountpoint then remount hidden at Audiobooks path
  if ! mount_at_audiobooks; then
    # Fallback if mount_apfs nobrowse fails
    /usr/sbin/diskutil unmount "/Volumes/${ABE_VOLUME_NAME}" >/dev/null 2>&1 || true
    /usr/sbin/diskutil mount -mountPoint "${ABE_AUDIOBOOKS_PATH}" "${ABE_VOLUME_NAME}" \
      || mount_failed "mount_apfs and diskutil mount both failed"
  fi
  if audiobooks_is_mount; then
    local n
    n="$(find "${ABE_AUDIOBOOKS_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'sha1-*' | wc -l | tr -d ' ')"
    log "mounted OK; sha1 folders=${n}"
    notify "apple-books-external-mount" "Mounted (${n} books)"
  else
    mount_failed "volume attached but not mounted at Audiobooks path"
  fi

  # Catalog care. If Books ran while the media was absent, the catalog is
  # pruned: heal it from our latest backup when we have one. Otherwise it is
  # intact and worth backing up now.
  local paths
  paths="$(catalog_path_count)"
  if (( paths < ABE_CATALOG_MIN_PATHS )); then
    if [[ -f "${ABE_CATALOG_BACKUP_DIR}/latest/Books.plist" ]]; then
      log "catalog looks pruned (${paths} path entries) — auto-restoring from ${ABE_CATALOG_BACKUP_DIR}/latest"
      restore_catalog_from "${ABE_CATALOG_BACKUP_DIR}/latest" || log "auto-restore failed; run: $0 restore-catalog"
    else
      log "catalog looks pruned (${paths} path entries) and no agent backup exists — run: $0 restore-catalog"
      notify "apple-books-external-mount" "Books catalog pruned — run restore-catalog"
    fi
  else
    backup_catalog
  fi
}

cmd_unmount() {
  # Soft unmount: detach media from Audiobooks path but keep 25External plugged in.
  acquire_lock
  trap release_lock EXIT

  quit_books
  /bin/sync

  if audiobooks_is_mount; then
    backup_catalog
    /usr/sbin/diskutil unmount "${ABE_AUDIOBOOKS_PATH}" || /usr/sbin/diskutil unmount force "${ABE_AUDIOBOOKS_PATH}"
  fi
  # Also clear a stray default mount if present
  /usr/sbin/diskutil unmount "/Volumes/${ABE_VOLUME_NAME}" >/dev/null 2>&1 || true
  mkdir -p "${ABE_AUDIOBOOKS_PATH}"
  detach_image
  /bin/sync
  log "media unmounted from Audiobooks path (external drive still attached)"
  cmd_status
}

cmd_eject() {
  acquire_lock
  trap release_lock EXIT
  print -r -- "running" >"${ABE_EJECT_STATUS}"
  inhibit_mount 180

  # Fast path: nothing mounted at the usual volume paths.
  # Safe to unplug = no mounted volumes. diskutil may still list the UUID briefly.
  if [[ ! -d "/Volumes/${ABE_EXTERNAL_NAME}" ]] \
     && [[ ! -d "/Volumes/Time Machine" ]] \
     && ! audiobooks_is_mount; then
    if /usr/sbin/diskutil info "${ABE_EXTERNAL_UUID}" >/dev/null 2>&1; then
      local whole
      whole="$(/usr/sbin/diskutil info "${ABE_EXTERNAL_UUID}" 2>/dev/null | /usr/bin/awk -F': *' '/Part of Whole/{print $2; exit}')"
      log "volumes not mounted; ejecting attached disk ${whole:-${ABE_EXTERNAL_UUID}}"
      if [[ -n "${whole}" ]]; then
        /usr/sbin/diskutil eject "${whole}" 2>/dev/null || true
      fi
      /usr/sbin/diskutil eject "${ABE_EXTERNAL_UUID}" 2>/dev/null || true
      sleep 1
    else
      log "drive already absent — nothing to eject"
    fi
    # Volumes are gone → safe to unplug (even if USB still enumerates the disk).
    log "no volumes mounted — safe to unplug"
    print -r -- "ok" >"${ABE_EJECT_STATUS}"
    exit 0
  fi

  # Time Machine on the same physical disk blocks eject (sidebar spinner).
  if /usr/bin/tmutil status 2>/dev/null | /usr/bin/grep -q 'Running = 1'; then
    log "stopping Time Machine backup..."
    /usr/bin/tmutil stopbackup 2>/dev/null || true
    local i
    for i in {1..60}; do
      if ! /usr/bin/tmutil status 2>/dev/null | /usr/bin/grep -q 'Running = 1'; then
        log "Time Machine stopped"
        break
      fi
      sleep 1
    done
  fi

  quit_books
  /bin/sync

  if audiobooks_is_mount; then
    backup_catalog
    /usr/sbin/diskutil unmount "${ABE_AUDIOBOOKS_PATH}" || /usr/sbin/diskutil unmount force "${ABE_AUDIOBOOKS_PATH}" || true
  fi
  /usr/sbin/diskutil unmount "/Volumes/${ABE_VOLUME_NAME}" >/dev/null 2>&1 || true
  mkdir -p "${ABE_AUDIOBOOKS_PATH}"
  detach_image
  /bin/sync

  # Unmount Time Machine volume so the shared APFS container can eject.
  if [[ -d "/Volumes/Time Machine" ]]; then
    /usr/sbin/diskutil unmount "/Volumes/Time Machine" 2>/dev/null || \
      /usr/sbin/diskutil unmount force "/Volumes/Time Machine" 2>/dev/null || true
  fi

  # Eject the whole APFS container (both 25External + Time Machine).
  local whole
  whole="$(/usr/sbin/diskutil info "${ABE_EXTERNAL_UUID}" 2>/dev/null | /usr/bin/awk -F': *' '/Part of Whole/{print $2; exit}')"
  if [[ -n "${whole}" ]]; then
    log "ejecting whole disk ${whole}"
    /usr/sbin/diskutil eject "${whole}" 2>/dev/null || true
  fi
  if [[ -d "/Volumes/${ABE_EXTERNAL_NAME}" ]]; then
    /usr/sbin/diskutil eject "/Volumes/${ABE_EXTERNAL_NAME}" 2>/dev/null || \
      /usr/sbin/diskutil unmount force "/Volumes/${ABE_EXTERNAL_NAME}" 2>/dev/null || true
  fi

  /bin/sync
  sleep 1
  if [[ -d "/Volumes/${ABE_EXTERNAL_NAME}" ]] || [[ -d "/Volumes/Time Machine" ]]; then
    log "eject finished but volumes still mounted"
    print -r -- "partial" >"${ABE_EJECT_STATUS}"
    exit 1
  fi

  log "eject sequence finished — safe to unplug"
  print -r -- "ok" >"${ABE_EJECT_STATUS}"
}

cmd_ensure() {
  # Called by LaunchAgent every 30s: protect the catalog, then mount if the
  # external is present and the aside exists.
  guard_books
  if mount_inhibited; then
    log "ensure skipped — mount inhibited (eject cooldown)"
    exit 0
  fi
  if ! external_mounted; then
    exit 0
  fi
  if audiobooks_is_mount; then
    exit 0
  fi
  if [[ ! -d "${ABE_ASIDE_PATH}" ]]; then
    # Not cut over yet — do nothing quietly
    exit 0
  fi
  # If image is attached at /Volumes but not at Audiobooks, finish the mount.
  cmd_mount
}

usage() {
  print "Usage: $0 {status|mount|unmount|eject|ensure|backup-catalog|restore-catalog [source-dir]}"
  exit 2
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    status) cmd_status ;;
    mount) cmd_mount ;;
    unmount) cmd_unmount ;;
    eject) cmd_eject ;;
    ensure) cmd_ensure ;;
    backup-catalog) cmd_backup_catalog ;;
    restore-catalog) cmd_restore_catalog "${2:-}" ;;
    *) usage ;;
  esac
}

main "$@"

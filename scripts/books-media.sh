#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/config/books-media.env"

mkdir -p "${BOOKS_MEDIA_LOG_DIR}"
LOG="${BOOKS_MEDIA_LOG_DIR}/books-media.log"

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
  print -r -- "$until" >"${BOOKS_MEDIA_INHIBIT}"
}

mount_inhibited() {
  [[ -f "${BOOKS_MEDIA_INHIBIT}" ]] || return 1
  local until
  until="$(cat "${BOOKS_MEDIA_INHIBIT}" 2>/dev/null || print 0)"
  if [[ "$(date +%s)" -lt "${until}" ]]; then
    return 0
  fi
  rm -f "${BOOKS_MEDIA_INHIBIT}"
  return 1
}

have_lock() {
  if [[ -f "${BOOKS_MEDIA_LOCK}" ]]; then
    local oldpid
    oldpid="$(cat "${BOOKS_MEDIA_LOCK}" 2>/dev/null || true)"
    if [[ -n "${oldpid}" ]] && kill -0 "${oldpid}" 2>/dev/null; then
      return 0
    fi
    rm -f "${BOOKS_MEDIA_LOCK}"
  fi
  return 1
}

acquire_lock() {
  if have_lock; then
    log "another books-media run holds the lock; exiting"
    exit 0
  fi
  print -r -- $$ >"${BOOKS_MEDIA_LOCK}"
}

release_lock() {
  rm -f "${BOOKS_MEDIA_LOCK}"
}

external_mounted() {
  [[ -d "/Volumes/${BOOKS_MEDIA_EXTERNAL_NAME}" ]] || diskutil info "${BOOKS_MEDIA_EXTERNAL_UUID}" >/dev/null 2>&1
}

audiobooks_is_mount() {
  /sbin/mount | /usr/bin/grep -F " on ${BOOKS_AUDIOBOOKS_PATH} " >/dev/null
}

quit_books() {
  # Prefer killall only — avoid nested osascript AppleEvents when invoked from
  # the Eject Books Drive.app (that caused AppleEvent timed out -1712).
  /usr/bin/killall Books 2>/dev/null || true
  /usr/bin/killall com.apple.BKAgentService 2>/dev/null || true
  sleep 2
  /usr/bin/killall -9 Books 2>/dev/null || true
  /usr/bin/killall -9 com.apple.BKAgentService 2>/dev/null || true
  sleep 1
}

sweep_strays() {
  # Copy any sha1 folders that landed under the local Audiobooks dir while unmounted
  # onto the image volume (mounted temporarily at /Volumes) before bind-mounting.
  setopt LOCAL_OPTIONS NULL_GLOB
  local tmp_mount="/Volumes/${BOOKS_MEDIA_VOLUME_NAME}"
  if [[ ! -d "${BOOKS_AUDIOBOOKS_PATH}" ]]; then
    return 0
  fi
  if audiobooks_is_mount; then
    return 0
  fi
  # Ensure image volume is attached at default path for sweep destination
  if [[ ! -d "${tmp_mount}" ]]; then
    if [[ -d "${BOOKS_MEDIA_IMAGE}" ]]; then
      /usr/bin/hdiutil attach "${BOOKS_MEDIA_IMAGE}" >/dev/null
    fi
  fi
  if [[ ! -d "${tmp_mount}" ]]; then
    log "sweep skipped: volume not available at ${tmp_mount}"
    return 0
  fi
  local count=0
  local d
  for d in "${BOOKS_AUDIOBOOKS_PATH}"/sha1-*; do
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
  if /sbin/mount | /usr/bin/grep -F "${BOOKS_MEDIA_VOLUME_NAME}" >/dev/null; then
    return 0
  fi
  if [[ ! -d "${BOOKS_MEDIA_IMAGE}" ]]; then
    log "image missing: ${BOOKS_MEDIA_IMAGE} (is ${BOOKS_MEDIA_EXTERNAL_NAME} mounted?)"
    return 1
  fi
  /usr/bin/hdiutil attach -nobrowse "${BOOKS_MEDIA_IMAGE}" >/dev/null
}

mount_at_audiobooks() {
  local dev
  dev="$(/usr/sbin/diskutil info "${BOOKS_MEDIA_VOLUME_NAME}" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')"
  if [[ -z "${dev}" ]]; then
    log "cannot find device node for ${BOOKS_MEDIA_VOLUME_NAME}"
    return 1
  fi
  # Drop default /Volumes mount if present, then mount hidden at Audiobooks path
  /usr/sbin/diskutil unmount "/Volumes/${BOOKS_MEDIA_VOLUME_NAME}" >/dev/null 2>&1 || true
  /sbin/mount_apfs -o nobrowse,nodev,nosuid "${dev}" "${BOOKS_AUDIOBOOKS_PATH}"
}

detach_image() {
  /usr/bin/hdiutil detach "${BOOKS_MEDIA_IMAGE}" -force >/dev/null 2>&1 || true
  # Fallback: detach by volume device if needed
  local dev
  dev="$(/usr/sbin/diskutil info "${BOOKS_MEDIA_VOLUME_NAME}" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')"
  if [[ -n "${dev}" ]]; then
    /usr/bin/hdiutil detach "${dev}" -force >/dev/null 2>&1 || true
  fi
}

cmd_status() {
  print "external: $(external_mounted && print mounted || print absent) (/Volumes/${BOOKS_MEDIA_EXTERNAL_NAME})"
  print "image: ${BOOKS_MEDIA_IMAGE}"
  print "image exists: $([[ -d ${BOOKS_MEDIA_IMAGE} ]] && print yes || print no)"
  print "audiobooks path: ${BOOKS_AUDIOBOOKS_PATH}"
  if audiobooks_is_mount; then
    print "audiobooks mount: YES"
    /sbin/mount | /usr/bin/grep -F " on ${BOOKS_AUDIOBOOKS_PATH} "
  else
    print "audiobooks mount: no"
  fi
  print -n "sha1 folders visible: "
  find "${BOOKS_AUDIOBOOKS_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'sha1-*' 2>/dev/null | wc -l | tr -d ' '
  print "aside present: $([[ -d ${BOOKS_ASIDE_PATH} ]] && print yes || print no)"
  if [[ -d "${BOOKS_ASIDE_PATH}" ]]; then
    print -n "aside sha1 folders: "
    find "${BOOKS_ASIDE_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'sha1-*' 2>/dev/null | wc -l | tr -d ' '
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
    log "already mounted at ${BOOKS_AUDIOBOOKS_PATH}"
    exit 0
  fi

  # Production cutover expects local tree already moved to aside.
  if [[ ! -d "${BOOKS_ASIDE_PATH}" ]]; then
    log "aside missing (${BOOKS_ASIDE_PATH}); refusing automatic cutover"
    notify "BooksMedia" "Aside missing — mount aborted"
    exit 1
  fi

  quit_books
  attach_image || {
    notify "BooksMedia" "Failed to attach image"
    exit 1
  }
  sweep_strays

  if [[ -d "${BOOKS_AUDIOBOOKS_PATH}" ]] && ! audiobooks_is_mount; then
    # Should be empty local dir after cutover
    rm -rf "${BOOKS_AUDIOBOOKS_PATH}"
  fi
  mkdir -p "${BOOKS_AUDIOBOOKS_PATH}"

  # Unmount default /Volumes mountpoint then remount hidden at Audiobooks path
  mount_at_audiobooks || {
    # Fallback if mount_apfs nobrowse fails
    /usr/sbin/diskutil unmount "/Volumes/${BOOKS_MEDIA_VOLUME_NAME}" >/dev/null 2>&1 || true
    /usr/sbin/diskutil mount -mountPoint "${BOOKS_AUDIOBOOKS_PATH}" "${BOOKS_MEDIA_VOLUME_NAME}"
  }
  if audiobooks_is_mount; then
    local n
    n="$(find "${BOOKS_AUDIOBOOKS_PATH}" -mindepth 1 -maxdepth 1 -type d -name 'sha1-*' | wc -l | tr -d ' ')"
    log "mounted OK; sha1 folders=${n}"
    notify "BooksMedia" "Mounted (${n} books)"
  else
    log "mount failed"
    notify "BooksMedia" "Mount failed"
    exit 1
  fi
}

cmd_unmount() {
  # Soft unmount: detach media from Audiobooks path but keep 25External plugged in.
  acquire_lock
  trap release_lock EXIT

  quit_books
  /bin/sync

  if audiobooks_is_mount; then
    /usr/sbin/diskutil unmount "${BOOKS_AUDIOBOOKS_PATH}" || /usr/sbin/diskutil unmount force "${BOOKS_AUDIOBOOKS_PATH}"
  fi
  # Also clear a stray default mount if present
  /usr/sbin/diskutil unmount "/Volumes/${BOOKS_MEDIA_VOLUME_NAME}" >/dev/null 2>&1 || true
  mkdir -p "${BOOKS_AUDIOBOOKS_PATH}"
  detach_image
  /bin/sync
  log "media unmounted from Audiobooks path (external drive still attached)"
  cmd_status
}

cmd_eject() {
  acquire_lock
  trap release_lock EXIT
  print -r -- "running" >"${BOOKS_MEDIA_EJECT_STATUS}"
  inhibit_mount 180

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
    /usr/sbin/diskutil unmount "${BOOKS_AUDIOBOOKS_PATH}" || /usr/sbin/diskutil unmount force "${BOOKS_AUDIOBOOKS_PATH}" || true
  fi
  /usr/sbin/diskutil unmount "/Volumes/${BOOKS_MEDIA_VOLUME_NAME}" >/dev/null 2>&1 || true
  mkdir -p "${BOOKS_AUDIOBOOKS_PATH}"
  detach_image
  /bin/sync

  # Unmount Time Machine volume so the shared APFS container can eject.
  if [[ -d "/Volumes/Time Machine" ]]; then
    /usr/sbin/diskutil unmount "/Volumes/Time Machine" 2>/dev/null || \
      /usr/sbin/diskutil unmount force "/Volumes/Time Machine" 2>/dev/null || true
  fi

  # Eject the whole APFS container (both 25External + Time Machine).
  local whole
  whole="$(/usr/sbin/diskutil info "${BOOKS_MEDIA_EXTERNAL_UUID}" 2>/dev/null | /usr/bin/awk -F': *' '/Part of Whole/{print $2; exit}')"
  if [[ -n "${whole}" ]]; then
    log "ejecting whole disk ${whole}"
    /usr/sbin/diskutil eject "${whole}" 2>/dev/null || true
  fi
  if [[ -d "/Volumes/${BOOKS_MEDIA_EXTERNAL_NAME}" ]]; then
    /usr/sbin/diskutil eject "/Volumes/${BOOKS_MEDIA_EXTERNAL_NAME}" 2>/dev/null || \
      /usr/sbin/diskutil unmount force "/Volumes/${BOOKS_MEDIA_EXTERNAL_NAME}" 2>/dev/null || true
  fi

  /bin/sync
  sleep 1
  if [[ -d "/Volumes/${BOOKS_MEDIA_EXTERNAL_NAME}" ]] || [[ -d "/Volumes/Time Machine" ]]; then
    log "eject finished but volumes still mounted"
    print -r -- "partial" >"${BOOKS_MEDIA_EJECT_STATUS}"
    exit 1
  fi

  log "eject sequence finished — safe to unplug"
  print -r -- "ok" >"${BOOKS_MEDIA_EJECT_STATUS}"
}

cmd_ensure() {
  # Called by LaunchAgent: if external is present and aside exists, mount.
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
  if [[ ! -d "${BOOKS_ASIDE_PATH}" ]]; then
    # Not cut over yet — do nothing quietly
    exit 0
  fi
  # If image is attached at /Volumes but not at Audiobooks, finish the mount.
  cmd_mount
}

usage() {
  print "Usage: $0 {status|mount|unmount|eject|ensure}"
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
    *) usage ;;
  esac
}

main "$@"

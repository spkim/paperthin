#!/bin/sh
# paperthin core installer and environment doctor. POSIX sh; no Node/Homebrew required.
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
MODE=install
TARGETS=all
METHOD=link
OVERWRITE=0
COMPAT=0
MODE_SEEN=0
DEST_ROOT=${PAPERTHIN_DEST_ROOT:-}
BACKUP_ROOT=
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  printf '%s\n' \
    'Usage: ./install.sh [--claude|--codex|--all] [--copy] [--compat] [--overwrite]' \
    '       ./install.sh --doctor [--compat]' \
    '       ./install.sh --uninstall [--claude|--codex|--all]' \
    '' \
    'Core installation needs only a POSIX shell and file utilities.' \
    'Existing unmanaged skill entries are skipped unless --overwrite is explicit.'
}

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS  %s\n' "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); printf 'WARN  %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL  %s\n' "$*" >&2; }
command_version() {
  command_name=$1
  if command -v "$command_name" >/dev/null 2>&1; then
    version_all=$($command_name --version 2>&1) || return 1
    version_output=$(printf '%s\n' "$version_all" | sed -n '1p')
    [ -n "$version_output" ] || version_output='present (version unavailable)'
    printf '%s' "$version_output"
    return 0
  fi
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --claude) TARGETS=claude ;;
    --codex) TARGETS=codex ;;
    --all) TARGETS=all ;;
    --doctor) [ "$MODE_SEEN" -eq 0 ] || { echo 'error: choose only one action' >&2; exit 2; }; MODE=doctor; MODE_SEEN=1 ;;
    --uninstall) [ "$MODE_SEEN" -eq 0 ] || { echo 'error: choose only one action' >&2; exit 2; }; MODE=uninstall; MODE_SEEN=1 ;;
    --copy) METHOD=copy ;;
    --compat) COMPAT=1 ;;
    --overwrite) OVERWRITE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

home_dir() {
  if [ -n "$DEST_ROOT" ]; then printf '%s' "$DEST_ROOT"; else printf '%s' "${HOME:?HOME is required}"; fi
}

claude_dir() { printf '%s/.claude/skills' "$(home_dir)"; }
codex_dir() { printf '%s/.codex/skills' "$(home_dir)"; }

doctor() {
  os_name=${PAPERTHIN_TEST_OS:-$(uname -s 2>/dev/null || printf unknown)}
  arch_name=${PAPERTHIN_TEST_ARCH:-$(uname -m 2>/dev/null || printf unknown)}
  shell_name=${PAPERTHIN_TEST_SHELL:-${SHELL:-unknown}}
  pass "OS=$os_name architecture=$arch_name shell=$shell_name"

  if [ "$os_name" = Darwin ]; then
    mac_version=${PAPERTHIN_TEST_MACOS_VERSION:-$(sw_vers -productVersion 2>/dev/null || printf unknown)}
    case "$mac_version" in
      11.*) warn "macOS=$mac_version (legacy host: core skills can install; verify each optional CLI/browser separately)" ;;
      unknown) warn 'macOS version unavailable' ;;
      *) pass "macOS=$mac_version" ;;
    esac
  fi

  if [ "${PAPERTHIN_TEST_NODE:-auto}" = missing ]; then
    warn 'Node.js=missing (core install remains available; npx-based distribution and Node adapters are unavailable)'
  elif [ "${PAPERTHIN_TEST_NODE:-auto}" != auto ]; then
    warn "Node.js=${PAPERTHIN_TEST_NODE} (diagnostic only; check the selected CLI's published requirements)"
  elif node_text=$(command_version node); then
    pass "Node.js=$node_text"
  else
    warn 'Node.js=missing (core install remains available; npx-based distribution and Node adapters are unavailable)'
  fi

  if [ "${PAPERTHIN_TEST_NPM:-auto}" = missing ]; then
    warn 'npm=missing (not required for core install)'
  elif [ "${PAPERTHIN_TEST_NPM:-auto}" != auto ]; then
    warn "npm=${PAPERTHIN_TEST_NPM} (not required for core install)"
  elif npm_text=$(command_version npm); then pass "npm=$npm_text"; else warn 'npm=missing (not required for core install)'; fi

  if [ "${PAPERTHIN_TEST_CLAUDE:-auto}" = missing ]; then
    warn 'Claude Code=missing (Claude target may still be prepared for later use)'
  elif [ "${PAPERTHIN_TEST_CLAUDE:-auto}" != auto ]; then
    pass "Claude Code=${PAPERTHIN_TEST_CLAUDE}"
  elif claude_text=$(command_version claude); then pass "Claude Code=$claude_text"; else warn 'Claude Code=missing (Claude target may still be prepared for later use)'; fi

  if [ "${PAPERTHIN_TEST_CODEX:-auto}" = missing ]; then
    warn 'Codex=missing (Codex target may still be prepared for later use)'
  elif [ "${PAPERTHIN_TEST_CODEX:-auto}" != auto ]; then
    pass "Codex=${PAPERTHIN_TEST_CODEX}"
  elif codex_text=$(command_version codex); then pass "Codex=$codex_text"; else warn 'Codex=missing (Codex target may still be prepared for later use)'; fi

  if [ "$COMPAT" -eq 1 ] || [ "${PAPERTHIN_TEST_NATIVE_AGENTS:-unknown}" = no ]; then
    warn 'agent isolation=compatibility mode (sequential supervisor/worker/reviewer remains available)'
  elif [ "${PAPERTHIN_TEST_NATIVE_AGENTS:-unknown}" = yes ]; then
    pass 'agent isolation=native capability declared by host/test environment'
  else
    warn 'agent isolation=runtime-selected (doctor does not guess support from CLI version; use --compat to force sequential roles)'
  fi

  chrome_found=0
  if [ "${PAPERTHIN_TEST_CHROME:-auto}" = present ]; then chrome_found=1
  elif [ "${PAPERTHIN_TEST_CHROME:-auto}" = auto ]; then
    for chrome_path in \
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
      '/Applications/Chromium.app/Contents/MacOS/Chromium'; do
      if [ -x "$chrome_path" ]; then chrome_found=1; break; fi
    done
  fi
  if [ "$chrome_found" -eq 1 ]; then
    pass 'system Chrome/Chromium executable found (possible browser-E2E fallback; project configuration still required)'
  else
    warn 'browser E2E=optional; no system Chrome/Chromium detected and Playwright browser compatibility was not assumed'
  fi

  pass 'core catalog=installable without Node, npm, Playwright, browser, or native subagents'
  printf 'SUMMARY PASS=%s WARN=%s FAIL=%s\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  [ "$FAIL_COUNT" -eq 0 ]
}

manifest_link_target() {
  manifest=$1
  wanted=$2
  [ -f "$manifest" ] || return 1
  awk -F '\t' -v name="$wanted" '$1 == name && $2 == "link" { print $3; found=1; exit } END { if (!found) exit 1 }' "$manifest"
}

is_managed() {
  entry=$1
  expected_name=$2
  manifest=$3
  if [ -L "$entry" ]; then
    link_value=$(readlink "$entry" 2>/dev/null || printf '')
    recorded_link=$(manifest_link_target "$manifest" "$expected_name" 2>/dev/null || printf '')
    [ -n "$recorded_link" ] && [ "$link_value" = "$recorded_link" ] && return 0
    case "$link_value" in
      "$ROOT"/skills/*/"$expected_name") [ -f "$link_value/SKILL.md" ] && return 0 ;;
    esac
  elif [ -f "$entry/.paperthin-managed" ]; then
    marker_head=$(sed -n '1p' "$entry/.paperthin-managed" 2>/dev/null)
    marker_name=$(sed -n '2s/^name=//p' "$entry/.paperthin-managed" 2>/dev/null)
    [ "$marker_head" = PAPERTHIN_MANAGED_V1 ] && [ "$marker_name" = "$expected_name" ] && return 0
  fi
  return 1
}

backup_entry() {
  entry=$1
  if [ -z "$BACKUP_ROOT" ]; then
    stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || printf now)
    BACKUP_ROOT="$(home_dir)/.re0/backups/paperthin-$stamp-$$"
    mkdir -p "$BACKUP_ROOT" || return 1
  fi
  dest_group=$(basename "$(dirname "$entry")")
  mkdir -p "$BACKUP_ROOT/$dest_group" || return 1
  mv "$entry" "$BACKUP_ROOT/$dest_group/$(basename "$entry")"
}

install_into() {
  dest=$1
  label=$2
  manifest=$dest/.paperthin-manifest-v1
  manifest_new=$(mktemp "${TMPDIR:-/tmp}/paperthin-manifest.XXXXXX") || { fail "$label could not create temporary manifest"; return 1; }
  printf 'PAPERTHIN_MANIFEST_V1\n' > "$manifest_new" || { fail "$label could not create temporary manifest"; return 1; }
  if ! mkdir -p "$dest"; then fail "$label destination cannot be created: $dest"; return 1; fi
  installed=0
  skipped=0
  for skill_file in "$ROOT"/skills/*/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    src=$(dirname "$skill_file")
    name=$(basename "$src")
    target="$dest/$name"
    if [ -e "$target" ] || [ -L "$target" ]; then
      if is_managed "$target" "$name" "$manifest"; then
        if [ "$METHOD" = link ] && [ -L "$target" ] && [ "$(readlink "$target" 2>/dev/null || printf '')" = "$src" ]; then
          printf '%s\tlink\t%s\n' "$name" "$src" >> "$manifest_new"
          installed=$((installed + 1)); continue
        fi
        backup_entry "$target" || { fail "$label could not back up managed entry: $target"; return 1; }
      elif [ "$OVERWRITE" -eq 1 ]; then
        backup_entry "$target" || { fail "$label could not back up conflicting entry: $target"; return 1; }
      else
        warn "$label skipped unmanaged conflict: $target (use --overwrite to back it up and replace it)"
        skipped=$((skipped + 1)); continue
      fi
    fi
    if [ "$METHOD" = copy ]; then
      cp -R "$src" "$target" || { fail "$label could not copy $name"; return 1; }
      printf 'PAPERTHIN_MANAGED_V1\nname=%s\nsource=%s\n' "$name" "$src" > "$target/.paperthin-managed" || { fail "$label could not mark $name"; return 1; }
    else
      ln -s "$src" "$target" || { fail "$label could not link $name"; return 1; }
    fi
    printf '%s\t%s\t%s\n' "$name" "$METHOD" "$src" >> "$manifest_new"
    installed=$((installed + 1))
  done
  mv "$manifest_new" "$manifest" || { fail "$label could not write ownership manifest: $manifest"; return 1; }
  pass "$label core catalog ready: $installed managed, $skipped conflicts skipped at $dest"
}

uninstall_from() {
  dest=$1
  label=$2
  [ -d "$dest" ] || { pass "$label has no skill directory; nothing to uninstall"; return 0; }
  manifest=$dest/.paperthin-manifest-v1
  if [ ! -f "$manifest" ]; then
    warn "$label has no paperthin ownership manifest; refusing broad uninstall"
    return 0
  fi
  [ "$(sed -n '1p' "$manifest" 2>/dev/null)" = PAPERTHIN_MANIFEST_V1 ] || {
    warn "$label ownership manifest is invalid; refusing broad uninstall"
    return 0
  }
  removed=0
  manifest_tab=$(printf '\t')
  while IFS="$manifest_tab" read -r name install_method recorded_source; do
    [ "$name" = PAPERTHIN_MANIFEST_V1 ] && continue
    case "$name" in ''|*[!A-Za-z0-9_-]*) warn "$label ignored invalid manifest entry: $name"; continue ;; esac
    target="$dest/$name"
    if [ -e "$target" ] || [ -L "$target" ]; then
      if is_managed "$target" "$name" "$manifest"; then
        rm -rf "$target" || { fail "$label could not remove managed entry: $target"; return 1; }
        removed=$((removed + 1))
      else
        warn "$label preserved unmanaged entry: $target"
      fi
    fi
  done < "$manifest"
  rm -f "$manifest" || { fail "$label could not remove ownership manifest"; return 1; }
  pass "$label removed $removed paperthin-managed entries; user settings and unmanaged skills preserved"
}

run_targets() {
  action=$1
  result=0
  case "$TARGETS" in
    claude) "$action" "$(claude_dir)" 'Claude Code' || result=1 ;;
    codex) "$action" "$(codex_dir)" 'Codex' || result=1 ;;
    all)
      "$action" "$(claude_dir)" 'Claude Code' || result=1
      "$action" "$(codex_dir)" 'Codex' || result=1
      ;;
  esac
  return "$result"
}

write_mode_preference() {
  mode_dir="$(home_dir)/.re0"
  mkdir -p "$mode_dir" || { fail "cannot create paperthin state directory: $mode_dir"; return 1; }
  if [ "$COMPAT" -eq 1 ]; then mode_value=compatibility; else mode_value=auto; fi
  printf '%s\n' "$mode_value" > "$mode_dir/paperthin-mode" || { fail 'cannot write orchestration mode preference'; return 1; }
  pass "orchestration preference=$mode_value"
}

case "$MODE" in
  doctor) doctor ;;
  install)
    [ -d "$ROOT/skills" ] || { fail "skills directory missing under $ROOT"; exit 1; }
    doctor || exit 1
    run_targets install_into || exit 1
    write_mode_preference || exit 1
    [ -n "$BACKUP_ROOT" ] && warn "replaced entries were backed up under $BACKUP_ROOT"
    pass "installation complete; optional agent/browser integrations did not gate the core catalog"
    ;;
  uninstall)
    run_targets uninstall_from || exit 1
    mode_file="$(home_dir)/.re0/paperthin-mode"
    [ ! -f "$mode_file" ] || rm -f "$mode_file" || { fail 'could not remove paperthin mode preference'; exit 1; }
    ;;
esac

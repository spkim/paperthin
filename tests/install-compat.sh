#!/bin/sh
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)
tmp=${TMPDIR:-/tmp}/paperthin-install-test-$$
trap 'rm -rf "$tmp"' 0 1 2 3 15
mkdir -p "$tmp"
fail=0

expect() {
  name=$1
  pattern=$2
  shift 2
  output_file=$tmp/output
  if "$@" > "$output_file" 2>&1 && grep -qF "$pattern" "$output_file"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    sed -n '1,120p' "$output_file" >&2
    fail=1
  fi
}

expect 'current host doctor' 'SUMMARY PASS=' "$ROOT/install.sh" --doctor
expect 'Big Sur and old Node warn, core remains available' 'core catalog=installable' \
  env PAPERTHIN_TEST_OS=Darwin PAPERTHIN_TEST_MACOS_VERSION=11.7.10 PAPERTHIN_TEST_NODE=v12.22.0 PAPERTHIN_TEST_NPM=6.14.0 PAPERTHIN_TEST_CLAUDE=missing PAPERTHIN_TEST_CODEX=missing "$ROOT/install.sh" --doctor --compat
expect 'Node absent' 'Node.js=missing' env PAPERTHIN_TEST_NODE=missing "$ROOT/install.sh" --doctor
expect 'Claude only' 'Codex=missing' env PAPERTHIN_TEST_CLAUDE=1.2.3 PAPERTHIN_TEST_CODEX=missing "$ROOT/install.sh" --doctor
expect 'Codex only' 'Claude Code=missing' env PAPERTHIN_TEST_CLAUDE=missing PAPERTHIN_TEST_CODEX=1.2.3 "$ROOT/install.sh" --doctor
expect 'both CLIs' 'Codex=1.2.3' env PAPERTHIN_TEST_CLAUDE=1.2.3 PAPERTHIN_TEST_CODEX=1.2.3 "$ROOT/install.sh" --doctor
expect 'native agent unavailable fallback' 'agent isolation=compatibility mode' env PAPERTHIN_TEST_NATIVE_AGENTS=no "$ROOT/install.sh" --doctor
expect 'Playwright/browser unavailable is optional' 'browser E2E=optional' env PAPERTHIN_TEST_CHROME=missing "$ROOT/install.sh" --doctor
expect 'system Chrome fallback detected' 'system Chrome/Chromium executable found' env PAPERTHIN_TEST_CHROME=present "$ROOT/install.sh" --doctor

home_a=$tmp/home-a
mkdir -p "$home_a/.claude/skills/re0-supervisor"
printf 'user-owned\n' > "$home_a/.claude/skills/re0-supervisor/KEEP"
expect 'unmanaged conflict is preserved' 'skipped unmanaged conflict' env PAPERTHIN_DEST_ROOT="$home_a" "$ROOT/install.sh" --claude --copy
[ -f "$home_a/.claude/skills/re0-supervisor/KEEP" ] || { echo 'FAIL  unmanaged file was not preserved' >&2; fail=1; }
[ -f "$home_a/.claude/skills/re0-worker/SKILL.md" ] || { echo 'FAIL  new skill did not install' >&2; fail=1; }

expect 'managed copy reinstall succeeds with backup' 'core catalog ready:' env PAPERTHIN_DEST_ROOT="$home_a" "$ROOT/install.sh" --claude --copy
expect 'managed uninstall succeeds' 'paperthin-managed entries' env PAPERTHIN_DEST_ROOT="$home_a" "$ROOT/install.sh" --uninstall --claude
[ -f "$home_a/.claude/skills/re0-supervisor/KEEP" ] || { echo 'FAIL  uninstall removed unmanaged entry' >&2; fail=1; }
[ ! -e "$home_a/.claude/skills/re0-worker" ] || { echo 'FAIL  uninstall left managed skill' >&2; fail=1; }

home_b=$tmp/home-b
expect 'all targets install without optional dependencies' 'installation complete' env PAPERTHIN_DEST_ROOT="$home_b" PAPERTHIN_TEST_NODE=missing PAPERTHIN_TEST_CHROME=missing "$ROOT/install.sh" --all --compat
[ -f "$home_b/.claude/skills/re0-worker/SKILL.md" ] && [ -f "$home_b/.codex/skills/re0-reviewer/SKILL.md" ] || { echo 'FAIL  all targets missing new roles' >&2; fail=1; }
[ "$(sed -n '1p' "$home_b/.re0/paperthin-mode")" = compatibility ] || { echo 'FAIL  compatibility preference was not persisted' >&2; fail=1; }

home_c=$tmp/home-c
expect 'default symlink install' 'installation complete' env PAPERTHIN_DEST_ROOT="$home_c" "$ROOT/install.sh" --all
[ -L "$home_c/.claude/skills/re0-supervisor" ] && [ -L "$home_c/.codex/skills/re0-supervisor" ] || { echo 'FAIL  default install did not create managed links' >&2; fail=1; }
expect 'symlink uninstall' 'paperthin-managed entries' env PAPERTHIN_DEST_ROOT="$home_c" "$ROOT/install.sh" --uninstall --all
[ ! -e "$home_c/.re0/paperthin-mode" ] || { echo 'FAIL  uninstall left mode preference' >&2; fail=1; }

home_d=$tmp/home-d
expect 'install before source relocation simulation' 'installation complete' env PAPERTHIN_DEST_ROOT="$home_d" "$ROOT/install.sh" --claude
ln -s "$tmp/missing-old-source" "$home_d/.claude/skills/retired-paperthin-skill"
printf 'retired-paperthin-skill\tlink\t%s\n' "$tmp/missing-old-source" >> "$home_d/.claude/skills/.paperthin-manifest-v1"
expect 'manifest removes retired and broken managed links' 'paperthin-managed entries' env PAPERTHIN_DEST_ROOT="$home_d" "$ROOT/install.sh" --uninstall --claude
[ ! -L "$home_d/.claude/skills/retired-paperthin-skill" ] || { echo 'FAIL  stale managed link survived uninstall' >&2; fail=1; }

home_e=$tmp/home-e
mkdir -p "$home_e/.claude/skills/re0-supervisor"
printf 'not-paperthin\n' > "$home_e/.claude/skills/re0-supervisor/.paperthin-managed"
printf 'keep\n' > "$home_e/.claude/skills/re0-supervisor/KEEP"
expect 'invalid marker does not grant ownership' 'skipped unmanaged conflict' env PAPERTHIN_DEST_ROOT="$home_e" "$ROOT/install.sh" --claude --copy
[ -f "$home_e/.claude/skills/re0-supervisor/KEEP" ] || { echo 'FAIL  invalid marker allowed replacement' >&2; fail=1; }

home_f=$tmp/home-f
expect 'install before user symlink replacement' 'installation complete' env PAPERTHIN_DEST_ROOT="$home_f" "$ROOT/install.sh" --claude
rm "$home_f/.claude/skills/re0-supervisor"
ln -s "$tmp/user-owned-target" "$home_f/.claude/skills/re0-supervisor"
expect 'user-replaced symlink is preserved' 'preserved unmanaged entry' env PAPERTHIN_DEST_ROOT="$home_f" "$ROOT/install.sh" --uninstall --claude
[ -L "$home_f/.claude/skills/re0-supervisor" ] || { echo 'FAIL  uninstall removed user-replaced symlink' >&2; fail=1; }

home_g=$tmp/home-g
mkdir -p "$home_g/.claude/skills"
ln -s "$ROOT/skills/coil/re0-worker" "$home_g/.claude/skills/re0-supervisor"
expect 'wrong-name repository symlink is unmanaged' 'skipped unmanaged conflict' env PAPERTHIN_DEST_ROOT="$home_g" "$ROOT/install.sh" --claude
[ "$(readlink "$home_g/.claude/skills/re0-supervisor")" = "$ROOT/skills/coil/re0-worker" ] || { echo 'FAIL  wrong-name user symlink was replaced' >&2; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo '✓ installer compatibility scenarios passed'
else
  exit 1
fi

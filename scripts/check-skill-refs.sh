#!/bin/sh
# Portable catalog vocabulary and README reachability guards.
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0
count_skills=0
count_files=0
tmp_base=$(mktemp -d "${TMPDIR:-/tmp}/paperthin-refs.XXXXXX") || exit 1
skills_file=$tmp_base.skills
files_file=$tmp_base.files
tokens_file=$tmp_base.tokens
trap 'rm -rf "$tmp_base"' 0 1 2 3 15

find skills -name SKILL.md -type f | while IFS= read -r path; do basename "$(dirname "$path")"; done | sort -u > "$skills_file"
if [ ! -s "$skills_file" ]; then
  echo '::error::no shipped SKILL.md found under skills/' >&2
  exit 1
fi
[ -f README.md ] || { echo '::error::README.md missing at repo root' >&2; exit 1; }

{ find skills -name SKILL.md -type f; find docs -name '*.md' -type f 2>/dev/null; for top_md in ./*.md; do [ -f "$top_md" ] && printf '%s\n' "$top_md"; done; } | sort -u > "$files_file"

while IFS= read -r file; do
  count_files=$((count_files + 1))
  grep -oE '`[a-z][a-z0-9-]{1,}`' "$file" 2>/dev/null | tr -d '`' | sort -u > "$tokens_file"
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    grep -qxF "$token" "$skills_file" && continue
    case "$token" in
      *-*)
        while IFS= read -r skill; do
          case "$token" in
            "$skill"-?*|?*-"$skill")
              echo "::error::$file: backticked '$token' looks skill-shaped and near shipped skill '$skill' but does not resolve" >&2
              fail=1
              break
              ;;
          esac
        done < "$skills_file"
        ;;
    esac
  done < "$tokens_file"
done < "$files_file"

while IFS= read -r skill; do
  count_skills=$((count_skills + 1))
  grep -qF "\`$skill\`" README.md && continue
  grep -qE "\]\([^)]*/${skill}/SKILL\.md\)" README.md && continue
  echo "::error::README.md: shipped skill '$skill' is not reachable" >&2
  fail=1
done < "$skills_file"

if [ "$fail" -eq 0 ]; then
  echo "✓ catalog skill-token and README reachability guards passed ($count_skills shipped names, $count_files scanned files)"
else
  echo '✗ skill reference check failed'; exit 1
fi

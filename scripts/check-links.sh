#!/bin/sh
# Check supported inline and full-reference Markdown targets, including images,
# using BSD/POSIX-compatible tools.
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0
count=0
file_count=0
tmp_base=$(mktemp -d "${TMPDIR:-/tmp}/paperthin-links.XXXXXX") || exit 1
files_file=$tmp_base.files
content_file=$tmp_base.content
targets_file=$tmp_base.targets
refs_file=$tmp_base.refs
trap 'rm -rf "$tmp_base"' 0 1 2 3 15
err() { echo "::error::$*"; fail=1; }

{ find skills -name SKILL.md 2>/dev/null; find docs -name '*.md' 2>/dev/null; for top_md in ./*.md; do [ -f "$top_md" ] && printf '%s\n' "$top_md"; done; } | sort -u > "$files_file"
[ -s "$files_file" ] || { echo '::error::no Markdown files found'; exit 1; }

check_target() {
  file=$1
  dir=$2
  target=$3
  raw=${target%%\#*}
  raw=${raw%%\?*}
  case "$raw" in ""|http://*|https://*|//*|mailto:*|tel:*) return 0 ;; esac
  case "$raw" in /*) resolved=.$raw ;; *) resolved=$dir/$raw ;; esac
  [ -e "$resolved" ] || err "$file: link target '$target' does not resolve ($resolved)"
}

while IFS= read -r file; do
  file_count=$((file_count + 1))
  dir=$(dirname "$file")
  cp "$file" "$content_file"
  grep -oE '\]\([^)]+\)' "$content_file" 2>/dev/null | sed 's/^](//; s/)$//' > "$targets_file"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    check_target "$file" "$dir" "$target"
    count=$((count + 1))
  done < "$targets_file"

  sed -nE 's/^[[:space:]]*\[([^]]+)\]:[[:space:]]+([^[:space:]]+).*/\1\t\2/p' "$content_file" > "$refs_file"
  grep -oE '\]\[[^]]+\]' "$content_file" 2>/dev/null | sed 's/^\]\[//; s/\]$//' > "$targets_file"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    ref_target=$(awk -F '\t' -v key="$ref" '$1 == key { print $2; exit }' "$refs_file")
    if [ -z "$ref_target" ]; then
      err "$file: reference '[$ref]' has no matching definition"
    else
      check_target "$file" "$dir" "$ref_target"
    fi
    count=$((count + 1))
  done < "$targets_file"
done < "$files_file"

if [ "$fail" -eq 0 ]; then
  echo "✓ supported relative Markdown targets resolve ($count occurrences across $file_count files)"
else
  echo '✗ link check failed'; exit 1
fi

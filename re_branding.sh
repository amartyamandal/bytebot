#!/usr/bin/env bash
set -euo pipefail

# re_branding.sh
# Safe, targeted UI rebranding helper (non-breaking): replace visible "Bytebot" -> "Mybot"
# - Operates only under packages/bytebot-ui and scans .tsx .ts .mdx .css .jsx files
# - Does NOT touch package names, filenames, Docker/Helm manifests, env var keys or GHCR image names
# Usage:
#   From repo root: bash re_branding.sh
#   Or make executable: chmod +x re_branding.sh && ./re_branding.sh

cd "$(dirname "$0")"

echo "Rebranding helper: replacing visible 'Bytebot' -> 'Mybot' in packages/bytebot-ui (preview first)"

# Find candidate files
mapfile -t CANDIDATES < <(find packages/bytebot-ui -type f \( -iname '*.tsx' -o -iname '*.ts' -o -iname '*.mdx' -o -iname '*.css' -o -iname '*.jsx' -o -iname '*.html' \) -print)

if [ ${#CANDIDATES[@]} -eq 0 ]; then
  echo "No UI files found under packages/bytebot-ui. Exiting."
  exit 0
fi

# Find which of those contain the capitalized brand token "Bytebot" (case-sensitive)
mapfile -t TO_CHANGE < <(grep -Il "Bytebot" "${CANDIDATES[@]}" || true)

if [ ${#TO_CHANGE[@]} -eq 0 ]; then
  echo "No occurrences of the exact token 'Bytebot' found in UI files. Nothing to do."
  exit 0
fi

echo "Files that include the visible token 'Bytebot':"
for f in "${TO_CHANGE[@]}"; do
  echo "  $f"
done

read -r -p "Proceed to replace 'Bytebot' -> 'Mybot' in the above files? (y/N) " ANSWER
if [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]]; then
  echo "Aborted by user. No changes made."
  exit 0
fi

# Backup (git-aware): if repo is a git repo and has a clean index, we'll create a branch and commit later. Otherwise we make simple file backups.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Git repository detected. Changes will be visible as unstaged edits; you can review and commit them." 
else
  echo "Not a git repo. Creating .bak copies of each file so changes can be reverted." 
  for f in "${TO_CHANGE[@]}"; do
    cp -p -- "$f" "$f.bak" || true
  done
fi

# Perform replacement (case-sensitive: only 'Bytebot' -> 'Mybot')
for f in "${TO_CHANGE[@]}"; do
  echo "Updating: $f"
  sed -i 's/Bytebot/Mybot/g' "$f"
done

# Show a compact git diff or file diffs
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "\nChanges (git diff):"
  git --no-pager diff -- packages/bytebot-ui | sed -n '1,200p'
else
  echo "\nChanges saved; backups are at *.bak for each file. Showing unified diffs:"
  for f in "${TO_CHANGE[@]}"; do
    echo "--- $f.bak"; echo "+++ $f"; diff -u "$f.bak" "$f" || true
  done
fi

echo "\nDone. Review changes, run tests/build, and commit when ready."

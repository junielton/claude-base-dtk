#!/usr/bin/env bash
# Upload an image or video to GitHub's attachment store and print its
# https://github.com/user-attachments/assets/<uuid> URL — the same URL the web UI
# gives you on drag-and-drop.
#
# Uses the undocumented endpoint uploads.github.com/user-attachments/assets,
# which accepts the gh token. It is not part of the public API and may change;
# callers must treat a non-zero exit as "upload unavailable", not as fatal.
#
# Usage: upload-attachment.sh <file> [owner/repo]
set -euo pipefail

file=${1:?usage: upload-attachment.sh <file> [owner/repo]}
repo=${2:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}

[ -f "$file" ] || { echo "not a file: $file" >&2; exit 2; }

mime=$(file --brief --mime-type "$file")
case $mime in
  image/png | image/jpeg | image/gif | image/webp | image/svg+xml) ;;
  video/mp4 | video/quicktime | video/webm) ;;
  *) echo "unsupported type: $mime ($file)" >&2; exit 2 ;;
esac

repo_id=$(gh api "repos/$repo" --jq .id)
name=$(jq -rn --arg n "$(basename "$file")" '$n | @uri')

resp=$(curl -sS --fail-with-body -X POST \
  "https://uploads.github.com/user-attachments/assets?name=$name&content_type=$mime&repository_id=$repo_id" \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Accept: application/json" \
  --data-binary "@$file") || { echo "upload failed: $resp" >&2; exit 1; }

url=$(jq -r '.url // empty' <<<"$resp")
[ -n "$url" ] || { echo "no url in response: $resp" >&2; exit 1; }
echo "$url"

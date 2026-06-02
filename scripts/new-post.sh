#!/usr/bin/env bash
# Scaffold a new blog post (Q15.1).
#   make new-post t="Some Title"     or     bash scripts/new-post.sh "Some Title"
# Creates src/blog/YYYY-MM-DD-slug/index.org as a DRAFT.
set -euo pipefail
cd "$(dirname "$0")/.."

title="${*:-}"
[ -z "$title" ] && { echo "usage: new-post.sh \"Post Title\"" >&2; exit 1; }

date=$(date +%Y-%m-%d)
slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//')
dir="src/blog/${date}-${slug}"
[ -e "$dir" ] && { echo "already exists: $dir" >&2; exit 1; }
mkdir -p "$dir"

cat > "$dir/index.org" <<EOF
#+SETUPFILE: ../../../site/setupfile.org
#+TITLE: ${title}
#+DATE: ${date}
#+KEYWORDS: draft
#+DRAFT: t
# Remove the #+DRAFT line above to publish. Optional:
#+EPIGRAPH: A line that sets the mood.
# #+MATH: t    (uncomment if the post contains LaTeX math)

Opening paragraph.
EOF

echo "created $dir/index.org (DRAFT)"

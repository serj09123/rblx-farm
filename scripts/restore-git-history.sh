#!/bin/bash
# Restores the full git history of this project from skyheart-ranch.bundle.
# Run once from the project folder:  bash scripts/restore-git-history.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d .git ]; then
  echo "A .git folder already exists - nothing to do."
  exit 0
fi
if [ ! -f skyheart-ranch.bundle ]; then
  echo "skyheart-ranch.bundle not found in $(pwd)"
  exit 1
fi

git init -q -b main
git fetch -q ./skyheart-ranch.bundle main:refs/remotes/bundle/main
git reset -q --mixed bundle/main
git update-ref -d refs/remotes/bundle/main
echo "History restored:"
git log --oneline | head -n 12
echo
git status --short | head -n 20
echo "(empty status above = your files match the last commit)"

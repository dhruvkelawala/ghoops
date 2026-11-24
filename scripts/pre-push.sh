#!/bin/sh
# Pre-push gate for trunk-based development.
# The iPhone app build runs in the `mac` job of GitHub Checks.
set -eu
cd "$(git rev-parse --show-toplevel)"

GO=${GO:-/opt/homebrew/opt/go@1.27/bin/go}
[ -x "$GO" ] || GO=go

upstream=$(git rev-parse --verify --quiet origin/main || true)
if [ -z "$upstream" ]; then
  echo "pre-push: no origin/main to compare with; running every check"
  changed=ALL
else
  changed=$(git diff --name-only "$upstream"...HEAD)
fi
if [ -z "$changed" ]; then
  echo "pre-push: nothing new against origin/main"
  exit 0
fi

code=$(printf '%s\n' "$changed" | grep -Ev '^(docs/|site/)|\.md$' || true)
fixtures=$(printf '%s\n' "$changed" | grep '^fixtures/' || true)

if [ -z "$code" ] && [ -z "$fixtures" ]; then
  echo "pre-push: documentation only; checks skipped"
  exit 0
fi

echo "pre-push: make check"
make GO="$GO" check

if [ -n "$fixtures" ] || printf '%s\n' "$changed" | grep -Eq '^(ALL$|ios/)'; then
  echo "pre-push: make ios-core-test"
  make ios-core-test
fi
echo "pre-push: trunk gate passed"

#!/usr/bin/env bash
#
# push-to-github.sh — push this project to GitHub as ONE clean commit.
#
# Usage:
#   ./scripts/push-to-github.sh [REPO_URL]
#
# Default REPO_URL is the repo created for this project. Override it for your
# own fork:
#   ./scripts/push-to-github.sh git@github.com:you/your-repo.git
#
# NOTE: this force-pushes. It replaces whatever history is on the remote with a
# single commit containing this project. That is intentional — it cleans up the
# partial history left behind by an interrupted file-by-file upload.
#
set -euo pipefail

REPO_URL="${1:-https://github.com/MrUnkown-dev/mclauncher-ios.git}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Repository: $REPO_URL"
echo "==> Working dir: $ROOT"

if [[ ! -d .git ]]; then
  echo "==> Initialising git repository"
  git init -q
fi

# Make sure the generated Xcode project is never committed (it is recreated by
# `xcodegen generate`) and that no signing material sneaks in.
if ! grep -q "MCLauncher.xcodeproj" .gitignore 2>/dev/null; then
  printf '\nMCLauncher.xcodeproj/\n' >> .gitignore
fi

git add -A

if git diff --cached --quiet; then
  echo "==> Nothing to commit"
else
  git commit -q -m "MCLauncher iOS: lightweight Minecraft Java Edition launcher

SwiftUI launcher shell with a native JVM bridge.

- Offline and Microsoft (device-code OAuth) accounts
- Mojang version manifest, downloads with SHA-1 verification
- Per-instance mods / resourcepacks / shaderpacks / datapacks / saves
- In-app file manager with Files-app import
- Modrinth browser + installer, including .mrpack modpack installs
- Fabric / Forge / OptiFine profile merging
- Live console, controller bridge, renderer and performance settings

Build: xcodegen generate && xcodebuild (see BUILD.md)
CI:    .github/workflows/build-ipa.yml (unsigned IPA on a macOS runner)"
  echo "==> Committed"
fi

git branch -M main

git remote remove origin 2>/dev/null || true
git remote add origin "$REPO_URL"

echo "==> Pushing to origin/main (force)"
git push -u origin main --force

echo
echo "=============================================="
echo " Pushed: $REPO_URL"
echo " Next:   GitHub -> Actions -> 'Build iOS IPA' -> Run workflow"
echo "=============================================="

#!/bin/sh
# Explicit release target; never publish to the upstream repository.
set -eu
cd "$(dirname "$0")/.."
TAG=v1.5.3-zh.2
REPO=qidian2022/Compositor-ZH
[ -z "$(git status --porcelain)" ] || { echo 'Commit and review changes first.'; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}")" ] || { echo 'Release tag must match HEAD.'; exit 1; }
(cd dist && shasum -a 256 -c SHA256SUMS.txt)
gh release create "$TAG" "dist/Compositor-ZH-1.5.3-zh.2-arm64.zip" "dist/Compositor-ZH-1.5.3-zh.2-arm64.dmg" dist/SHA256SUMS.txt \
  --repo "$REPO" --verify-tag --prerelease \
  --title 'Compositor 中文版 1.5.3-zh.2（预览版）' --notes-file docs/release-1.5.3-zh.2.md

#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/package.sh <archive-version> <output-directory>" >&2
  exit 2
fi

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
archive_version=$1
output_directory=$2
package_directory="$output_directory/apple-notes-reminders"
archive="$output_directory/apple-notes-reminders-$archive_version-macos-universal.tar.gz"

cd "$repository_root"
mkdir -p "$package_directory"

swift build -c release --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
cp .build/apple/Products/Release/apple-notes-reminders "$package_directory/"
cp README.md LICENSE SECURITY.md "$package_directory/"
cp -R skills/apple-notes-reminders "$package_directory/"

codesign --force --sign - \
  --identifier dev.nmadelei.apple-notes-reminders \
  --entitlements Config/Release.entitlements \
  "$package_directory/apple-notes-reminders"
codesign --verify --strict --verbose=2 "$package_directory/apple-notes-reminders"
lipo -verify_arch arm64 x86_64 "$package_directory/apple-notes-reminders"

swift package show-dependencies --format json >"$output_directory/dependency-graph.json"
tar -C "$output_directory" -czf "$archive" apple-notes-reminders
shasum -a 256 "$archive" "$output_directory/dependency-graph.json" >"$output_directory/SHA256SUMS"

printf '%s\n' "$archive"

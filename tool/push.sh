#!/bin/sh
# Push flow: bump the VERSION (patch X.Y.Z -> X.Y.Z+1), commit (the pre-commit
# hook also bumps the build number), then push. Extra args pass through to push.
set -e
cd "$(git rev-parse --show-toplevel)"
pubspec="pubspec.yaml"
perl -i -pe 's/^(version:\s*\d+\.\d+\.)(\d+)(\+\d+)/$1 . ($2 + 1) . $3/e' "$pubspec"
git add "$pubspec"
git commit -m "Release: bump version"
git push "$@"
echo "Pushed $(grep '^version:' "$pubspec")"

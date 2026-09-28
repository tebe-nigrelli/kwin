#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
pkgroot=${PKGROOT:-"$HOME/build/topos/kwin"}
version=$(sed -nE 's/^set\(PROJECT_VERSION "([^"]+)"\).*/\1/p' "$source_dir/CMakeLists.txt")

test -n "$version"
test -d "$source_dir/src/topos"
test -f "$pkgroot/PKGBUILD"
grep -qx "pkgver=$version" "$pkgroot/PKGBUILD" || {
    echo "PKGBUILD does not match KWin $version" >&2
    exit 1
}

cd "$source_dir"
git diff --check
python -c 'import xml.etree.ElementTree as E; E.parse("src/org.kde.KWin.Topos.xml")'

dest="$pkgroot/src/kwin-$version"
test -d "$dest" || {
    echo "Missing $dest; run 'makepkg -os' in $pkgroot once first" >&2
    exit 1
}

rsync -a --delete --exclude=.git/ --exclude=build/ --exclude=.build/ \
    "$source_dir/" "$dest/"

cd "$pkgroot"
makepkg -eLsfi --check

echo "KWin $version is installed. Log out and back in to run it."

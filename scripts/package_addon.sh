set -euo pipefail
mkdir -p dist/QuickRoute
# Package the complete addon tree, including XML, source manifests and licenses.
# Tests/ also ships because the TOC exposes the in-game /qrtest command.
cp -r QuickRoute/. dist/QuickRoute/

entries=0
while IFS= read -r entry || [ -n "$entry" ]; do
  entry="${entry%$'\r'}"
  case "$entry" in ''|'#'*) continue ;; esac
  entries=$((entries + 1))
  path="dist/QuickRoute/${entry//\\//}"
  if [ ! -f "$path" ]; then
    echo "::error::QuickRoute.toc references $entry, which is not in the package"
    exit 1
  fi
done < QuickRoute/QuickRoute.toc
if [ "$entries" -lt 20 ]; then
  echo "::error::Read only $entries TOC entries; cannot verify package completeness"
  exit 1
fi
for required in Licenses/QuickRoute-MIT.txt Licenses/AllTheThings-MIT.txt \
  ThirdParty/Mapzeroth-LICENSE.txt ThirdParty/Mapzeroth-NOTICE.md \
  Data/DestinationCatalog.sources.txt; do
  if [ ! -s "dist/QuickRoute/$required" ]; then
    echo "::error::Required license or source notice missing: $required"
    exit 1
  fi
done
echo "Verified $entries TOC entries and required source notices"

cd dist
python3 -m zipfile -c "QuickRoute-${VERSION}.zip" QuickRoute
echo "Created QuickRoute-${VERSION}.zip ($(du -h "QuickRoute-${VERSION}.zip" | cut -f1))"

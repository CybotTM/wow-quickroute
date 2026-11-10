set -euo pipefail
mkdir -p dist/QuickRoute
# Package the complete addon tree, including XML, source manifests and licenses.
# Tests/ also ships because the TOC exposes the in-game /qrtest command.
cp -r QuickRoute/. dist/QuickRoute/

# Both TOCs: QuickRoute.toc for retail, QuickRoute_Camelot.toc for WoW Forever.
# One archive serves both clients; each client reads only its own TOC.
entries=0
for toc in QuickRoute.toc QuickRoute_Camelot.toc; do
  if [ ! -f "QuickRoute/$toc" ]; then
    echo "::error::$toc is missing"
    exit 1
  fi
  toc_entries=0
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%$'\r'}"
    case "$entry" in ''|'#'*) continue ;; esac
    toc_entries=$((toc_entries + 1))
    path="dist/QuickRoute/${entry//\\//}"
    if [ ! -f "$path" ]; then
      echo "::error::$toc references $entry, which is not in the package"
      exit 1
    fi
  done < "QuickRoute/$toc"
  if [ "$toc_entries" -lt 20 ]; then
    echo "::error::Read only $toc_entries entries from $toc; cannot verify package completeness"
    exit 1
  fi
  entries=$((entries + toc_entries))
done
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

#!/bin/bash
# Lint script for QuickRoute addon
# Run this before committing to catch Lua errors
#
# Fails closed: if no linter is available the script exits non-zero rather than
# letting the pre-commit hook pass on an unchecked tree. Set QR_LINT_OPTIONAL=1
# to downgrade that to a warning.

set -euo pipefail

# Keep this in step with .github/workflows/ci.yml, which pins the same version.
LUACHECK_VERSION="1.2.0"
LUACHECK_IMAGE="ghcr.io/lunarmodules/luacheck:v${LUACHECK_VERSION}"

echo "=== QuickRoute Linting ==="
echo ""

if [ "$#" -gt 0 ]; then
    FILES=("$@")
else
    FILES=("QuickRoute/" "tests/")
fi

if command -v luacheck &>/dev/null; then
    installed=$(luacheck --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    echo "Running luacheck ${installed:-unknown}..."
    if [ -n "$installed" ] && [ "$installed" != "$LUACHECK_VERSION" ]; then
        # CI pins one version; a local one that differs enforces different rules,
        # so a clean run here says nothing about the gate.
        echo "⚠ Local luacheck is ${installed}, CI pins ${LUACHECK_VERSION}." >&2
        echo "  Results may differ from the gate. Use the Docker invocation for parity." >&2
    fi
    luacheck "${FILES[@]}" --config .luacheckrc
    echo "✓ Luacheck passed"
elif command -v docker &>/dev/null; then
    echo "Running luacheck ${LUACHECK_VERSION} via Docker..."
    docker run --rm -v "$(pwd):/src" -w /src \
        "${LUACHECK_IMAGE}" "${FILES[@]}" --config .luacheckrc
    echo "✓ Luacheck passed"
elif [ "${QR_LINT_OPTIONAL:-0}" = "1" ]; then
    echo "⚠ luacheck not available and QR_LINT_OPTIONAL=1 — skipping" >&2
else
    echo "ERROR: luacheck is not available." >&2
    echo "  Install it (luarocks install luacheck ${LUACHECK_VERSION}) or start Docker." >&2
    echo "  Set QR_LINT_OPTIONAL=1 to skip this check deliberately." >&2
    exit 1
fi

echo ""
echo "=== Linting Complete ==="

#!/bin/bash
# Lint script for QuickRoute addon
# Run this before committing to catch Lua errors

set -e

echo "=== QuickRoute Linting ==="
echo ""

# Run luacheck: native binary, Docker fallback, or skip
FILES="${*:-QuickRoute/}"
if command -v luacheck &>/dev/null; then
    echo "Running luacheck..."
    luacheck $FILES --config .luacheckrc
    echo "✓ Luacheck passed"
elif command -v docker &>/dev/null; then
    echo "Running luacheck via Docker..."
    docker run --rm -v "$(pwd):/src" -w /src \
        pipelinecomponents/luacheck:latest luacheck $FILES
    echo "✓ Luacheck passed"
else
    echo "⚠ luacheck not available (install locally or have Docker running)"
fi

echo ""
echo "=== Linting Complete ==="

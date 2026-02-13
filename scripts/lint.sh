#!/bin/bash
# Lint script for QuickRoute addon
# Run this before committing to catch Lua errors

set -e

echo "=== QuickRoute Linting ==="
echo ""

# Check if luacheck is installed
if command -v luacheck &> /dev/null; then
    echo "Running luacheck..."
    luacheck QuickRoute/ --config .luacheckrc
    echo "✓ Luacheck passed"
else
    echo "⚠ luacheck not installed. Install with: luarocks install luacheck"
fi

echo ""

# Check Lua 5.1 syntax (WoW uses Lua 5.1)
if command -v lua5.1 &> /dev/null; then
    LUA_CMD="lua5.1"
elif command -v lua &> /dev/null; then
    LUA_CMD="lua"
else
    echo "⚠ Lua not installed, skipping syntax check"
    exit 0
fi

echo "Checking Lua 5.1 syntax compatibility..."
ERRORS=0
for file in $(find QuickRoute -name "*.lua"); do
    if ! $LUA_CMD -p "$file" 2>&1; then
        echo "✗ Syntax error in: $file"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo "✓ All Lua files have valid syntax"
else
    echo "✗ Found $ERRORS files with syntax errors"
    exit 1
fi

echo ""
echo "=== Linting Complete ==="

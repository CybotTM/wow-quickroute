## Summary

<!-- Brief description of the changes -->

## Type

- [ ] Bug fix
- [ ] New feature
- [ ] New teleport / portal data
- [ ] Localization
- [ ] Refactoring
- [ ] CI / build

## Testing

- [ ] All tests pass (`lua5.1 tests/run_tests.lua`)
- [ ] Tested in-game (if UI/gameplay change)
- [ ] New tests added (if applicable)

## Checklist

- [ ] No Lua 5.2+ features (goto, bitwise, //)
- [ ] Uses `QR.Colors`, `QR.L`, `QR.PlayerInfo` (no hardcoded values)
- [ ] Tooltips use `QR.AddTooltipBranding()` + `GameTooltip_Hide()`
- [ ] Click handlers include `PlaySound(SOUNDKIT.*)`

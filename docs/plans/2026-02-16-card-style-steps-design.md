# Card-Style Route Steps Design

## Goal
Replace the current single-line route step rendering (24px, cramped) with a card-style
two-line layout featuring larger icons and better-spaced buttons for improved readability.

## Layout (~48px per step)

```
┌──────────────────────────────────────────────────────────────┐
│  ┌──────┐                                                    │
│  │ 28×28 │  1. Use [Hearthstone]              [ Use ] [Nav]  │
│  │ icon  │  → Stormwind  ·  CD: 3:20                        │
│  └──────┘                                                    │
└──────────────────────────────────────────────────────────────┘
```

## Changes

| Element            | Before              | After                                    |
|--------------------|----------------------|------------------------------------------|
| Icon               | 16×16 inline texture | 28×28 standalone Texture frame            |
| Step height        | 24px                 | 48px base                                |
| Action (line 1)    | Single cramped line  | Dedicated line, GameFontNormal            |
| Destination (line 2)| Inline in action    | Own line, muted gray, → prefix + time    |
| Nav button         | 40×18                | 50×22                                    |
| Use button overlay | 38×22                | 50×22                                    |
| Current step       | > prefix             | Gold 3px left border highlight            |

## Anchoring

- Icon: TOPLEFT of stepFrame, (8, -10), 28×28 (8px leaves room for highlight border)
- Line 1: TOPLEFT of stepFrame, (icon offset + icon size + 6, -6), RIGHT stops at Nav button
- Line 2: TOPLEFT below line 1, same left edge, GameFontNormalSmall
- Nav button: TOPRIGHT of stepFrame (-5, -4), 50×22
- Use overlay: left of Nav, same vertical offset
- Current-step highlight: 3px left border Texture in gold (1, 0.82, 0)

## Unchanged

- Frame pool pattern
- SecureActionButton overlay pattern
- Word wrap growing height
- Scroll frame structure
- Tooltip behavior

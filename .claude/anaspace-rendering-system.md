# Anaspace — Rendering System Specification

## Overview

Anaspace uses a character-cell matrix as its fundamental rendering primitive. The entire UI (with limited exceptions) is built on a fixed grid of monospaced character cells, organized into three independent layers. The approach is closer to a 2D character-mode renderer with a thin SwiftUI shell for system integration than a conventional SwiftUI app.

---

## The Character Grid

### Typography

- **Font:** JetBrains Mono (1,736 glyphs across two weights)
- **Size:** 15.52pt
- **Letter spacing:** 11%
- **Line height:** 22.3pt
- **Result:** Roughly equal spacing between characters vertically and horizontally

### Grid Dimensions

- **Columns:** 33 (fixed across all devices)
- **Base device:** iPhone 17 Pro (402 × 874pt)
- **Top padding:** 63px (avoids camera/Dynamic Island)
- **Side margins:** 20px each
- **Bottom footer:** 97px (reserved for navigation, outside the grid)
- **Rows:** 32 on base device

### Responsiveness

The column count (33) is fixed. Row count is calculated dynamically based on available vertical space:

1. Determine safe area rectangle for the device
2. Subtract top padding and bottom footer
3. Divide remaining height by line height (22.3pt)
4. Result is the row count for that device

Most modern iPhones will land at 31–33 rows. The system should define a minimum viable screen (approximately 28 rows) and treat extra rows as bonus space.

### Row Independence

Each row is an independent rendering unit. No text wrapping occurs between rows. Changing one row never forces relayout of other rows. This enables granular control over per-row updates and transition animations.

### Cell Addressing

Every cell has an exact address: (column, row, layer). Every cell is the same size. A cell's visual state is fully described by three values: **layer**, **glyph**, **color**.

---

## The Three-Layer System

Three layers stack visually, all perfectly aligned to the same 33×N grid. Each layer is fully independent — no layer influences another layer's content or visibility. The only interaction between layers is visual stacking order.

### Layer 1 — Structure (Bottom)

- Provides visual form and texture to the screen
- Typically uses light colors
- Populated with structural glyphs to create shapes, grids, zones
- Mostly static — set when a screen loads, persists until the next major navigation
- Can be animated subtly during idle state (see Animation section)
- Controlled directly — content layer does not dictate what's visible here

### Layer 2 — Content (Middle)

- All meaningful information: entity names, labels, triad bar, descriptions
- Typically uses dark colors
- Relatively sparse against the full grid (structure peeks through gaps)
- Updates when content changes via navigation or interaction

### Layer 3 — Transition (Top)

- Temporary animation layer for screen transitions
- When active, visually covers layers below by having glyphs in those cells
- When inactive (no transition), completely empty — all cells pass through
- Constrained to the grid — remains inside the margins
- Does not extend into the bottom nav zone

### Compositing Rule

For any cell at position (column, row), the visible result is the topmost layer that has a non-empty glyph in that cell:

1. **Top layer** has a glyph → it wins, full stop
2. **Middle layer** has a glyph (top is empty) → it wins
3. **Bottom layer** has a glyph (top and middle are empty) → it wins
4. **All empty** → screen background color shows through

There is no opacity. Everything is 100% on/off. There is no blending between layers. A cell is either occupied by a glyph in a specific color, or it is empty.

There is no "blocking" mechanic — no layer uses space characters or blanks to mask layers beneath it. Empty means empty (passes through).

---

## Color System

Exactly five colors in the entire project. No gradients, no opacity, no additional colors. Every cell on screen resolves to one of five colors or empty (background).

The two font weights (regular and bold) provide an additional visual lever without adding a color — weight can reinforce layer identity or distinguish entity types.

---

## Rendering Architecture

### Approach: Core Animation with CATextLayer

Each row on each layer is a single `CATextLayer`. Total layer count: 32 rows × 3 layers = **96 CATextLayer instances**.

- Core Animation composites these at 60 FPS on the GPU automatically
- No custom Metal shaders or GPU code required
- Each row update changes the `string` property (as `NSAttributedString`) on one `CATextLayer`
- Unchanged layers are cached as GPU textures — no re-render cost
- Per-row `NSAttributedString` supports per-character color via attributes (up to 5 colors per row)

### Performance Budget

During the most intensive moment (full screen transition), the realistic per-frame cost is approximately 4–6 `CATextLayer` string mutations. Each takes well under 1ms. At 60 FPS there is 16.6ms per frame. There is substantial headroom.

### Optimization Strategies

- **Dirty region tracking:** Only re-render rows (and ideally cell ranges within rows) that have changed
- **Attributed string caching:** Cache `NSAttributedString` instances for rows that don't change; build target-state strings once rather than per-frame
- **Pre-computed screen states:** For known layouts, compute the solved cell arrangement and cache it; navigation becomes diff + animate changed cells
- **Row-level animation granularity:** Keep animation operations at the row level. Per-cell visual effects (like typewriter) should be implemented as sequential row-string updates, not individual cell animations
- **Avoid per-cell animation objects:** Do not create independent `CAAnimation` instances for individual cells (1,056 simultaneous animations would cause pressure)

### Screen State Data Model

With 5 colors and no opacity, a full screen state across all three layers is approximately 3KB of raw data (glyph index + color index per cell). Screen states can be snapshotted trivially, diffed cheaply, and stored in deep history without memory concerns.

---

## Glyph System

JetBrains Mono's full glyph set is available for text content (names, descriptions, labels). For decorative and symbolic use, define a curated subset that forms the Anaspace visual vocabulary:

- **Entity type icons:** Specific symbols mapped to Person, Work, Place, Event, Genre, etc.
- **Structural decoration:** Glyphs used for background texture and visual zones
- **Transition textures:** Glyphs used during animations, organized by visual density tier

### Density Tiers

Categorize glyphs into 4–5 tiers based on visual weight (how much "ink" they put on screen):

- **Tier 1 (minimal):** `·` `'` `,` — barely visible
- **Tier 2 (light):** `-` `~` `°` — sparse marks
- **Tier 3 (medium):** `+` `*` `#` `╬` — moderate coverage
- **Tier 4 (heavy):** `█` `▓` `▒` — near-solid fills
- **Tier 5 (solid):** Full block characters

Density tiers are used during transition animations and idle background animation. Randomizing within a density tier creates living texture that reads as consistent visual weight with organic variation.

---

## Animation System

Three distinct animation patterns, forming a clear energy hierarchy: idle (near-zero) → page transitions (medium) → observe (peak).

All three share a unified visual language: organic, textured, density-based glyph patterns — just at different intensities.

### Pattern 1: Observe Animation (Hero Transition)

**Trigger:** User presses the observe button.

**Behavior:** Simultaneously activates Shazam for music recognition and streams audio to Claude for voice/instruction parsing. Shazam can take up to 10 seconds. The animation runs continuously until results arrive.

**Visual concept:** Radial echolocation — concentric, organic rings of glyphs emanate outward from the observe button's position at the bottom center of the grid. Not literal radar — atmospheric and mood-driven. Glyphs are chosen by density tier to create intentional shapes that visualize flow and density. Within each density tier, specific glyphs are randomized to create living texture.

**Two-directional signal:**

- **Outbound (app reaching out):** Steady rhythmic pulses radiating from center to edges. Uses one of the five colors. Consistent rhythm regardless of audio input. Represents "I'm listening."
- **Inbound (audio response):** Waves originating from grid edges moving toward center. Uses a different color. Intensity driven by real-time audio amplitude:
  - Quiet room → sparse, faint activity at edges
  - Loud music → dense waves pushing deep toward center
  - Speech → rhythmic pulses matching cadence
- **Mixing zone:** Where outbound and inbound meet, cells may alternate between the two colors. The mixing zone shifts based on audio loudness, giving the animation a dynamic center of gravity.

**Audio-to-visual mapping:** RMS amplitude from the audio buffer, sampled 10–15 times per second, smoothed slightly. Maps to: how far inward from edges the inbound glyphs reach, and which density tier they draw from.

**Looping:** Each pulse cycle takes approximately 1.5–2 seconds. Over a 10-second window, 5–7 pulses occur. The rhythm communicates "still listening."

**Resolution:** When Shazam resolves, the inbound signal intensifies (final surge toward center), both patterns converge, then the transition layer clears to reveal the new content state prepared underneath.

**Voice input variant (press-hold-release):** Similar radial pattern but tighter, faster pulses concentrated toward center. Duration is user-controlled (runs while holding). Audio reactivity is more central — the user sees their voice arriving on screen as they speak. On release, brief processing moment, then result appears.

### Pattern 2: Page Transitions

**Trigger:** Navigation between distinct screen states.

**Behavior:** Fast, slightly chaotic transitions using Perlin noise to generate cloud-like shapes that swirl across the page.

**Visual concept:** A Perlin noise field maps to glyph density — high noise values produce dense glyphs, low values produce sparse glyphs, values below a threshold (~0.3) produce empty cells. This creates organic cloud shapes with natural gaps and irregular edges.

**Motion:** The noise field's sample coordinates animate over time, creating flowing/drifting movement. Clouds of glyphs roll across the screen, covering current content momentarily. While covered, content and structure layers swap to their new state. Clouds continue rolling off to reveal the new screen.

**Three-phase structure:**
1. **Cover:** Noise clouds roll in, progressively hiding current content
2. **Swap:** Content and structure layers update instantly while hidden
3. **Reveal:** Noise clouds roll away, revealing new content

**Timing:** 300–400ms total. Fast enough to feel quick, textured enough to feel organic.

**Performance optimization:** Pre-compute noise textures larger than the grid (e.g., 66×64). Sample different 33×32 windows by shifting the offset each frame — just an index lookup, not real-time noise computation. Pre-compute several noise textures for variety.

### Pattern 3: Idle State (Ready to Observe)

**Trigger:** App is open, waiting for user action. Content layer shows minimal centered text.

**Behavior:** Subtle animation on the background (structure) layer only. Uses the same Perlin noise approach as page transitions, but at very low intensity and slow speed.

**Visual concept:** Background structural glyphs shift slowly — small regions swap between glyphs of similar density as a noise field drifts through. Most of the background is static at any moment; small patches breathe. Should feel like looking at water — movement is perceptible in peripheral vision but hard to track in direct focus.

**Rate:** Approximately 1–2 cell changes per row per second, distributed unevenly following the noise field.

---

## Non-Grid Elements

Three elements exist outside or overlaid on the character grid. All respect the grid's coordinate system in some way.

### 1. Bottom Navigation

- Lives in the 97px footer zone **below the grid entirely**
- Not part of the character matrix — separate UI region
- Three actions on main screen (history, observe, options)
- Contextual actions on other screens (back, zoom, etc.)
- Has its own independent animation when pressed (not connected to grid animations)
- Remains stable during grid transitions — does not participate in transition layer animations
- The observe button is the prominent central element (circle); flanking actions use JetBrains Mono glyphs at consistent visual weight with the grid
- The observe animation's radial pulses begin at the boundary between nav and grid (first ring appears at the bottom row of the grid)

### 2. Year Indicator

- 4-character date display in a **different font** from JetBrains Mono
- Positioned at top right of the main (subject) screen
- Occupies a 4-column × 3-row cell region (characters centered within)
- Treated as a reserved zone: content and structure layers leave those 12 cells empty
- Renders as an overlay positioned to align with grid coordinates
- Does not participate in layer compositing — floats above everything
- The font difference signals that the year is a coordinate/landmark, not content to read
- Has its own transition when the year changes (independent of grid transitions) — digits can flip/cycle individually
- **Tap target includes the year numbers and extends into surrounding area**

### 3. Overlay Buttons

- Same height as grid cells
- Text/icons in a smaller JetBrains Mono, spaced to align with grid columns
- Snap to cell boundaries but rendered as continuous overlay elements (not composed of individual cells)
- Positioned using grid coordinates for their frame (e.g., "start at column 0, row 14, span 10 columns, 1 row")
- The grid doesn't know about them — they sit above the grid layers
- **Tap targets extend beyond the visible button.** Example: the "LOCATION" button's tap target includes the map area above it. The "YEAR" button's tap target includes the year indicator. Hit areas are deliberately large.

### Visual Stack (back to front)

1. Screen background color
2. Grid bottom layer (structure)
3. Grid middle layer (content)
4. Grid top layer (transition)
5. Overlay buttons (contextual)
6. Year indicator
7. Bottom navigation

---

## Accessibility

The fixed grid intentionally does not support Dynamic Type — the grid **is** the interface, and scaling it would break the system. Accessibility accommodations happen through other means:

- **VoiceOver:** Semantic descriptions of what the grid is showing (not individual cell readings)
- **High contrast:** Adjusted color values within the existing 5-color palette
- **Reduced motion:** Simplified or disabled transition animations

---

## Technical Notes

### SwiftUI Shell Role

SwiftUI handles: system integration (permissions, navigation, status bar), the bottom navigation bar, overlay buttons, and any modal/sheet presentations. The core grid experience is rendered via Core Animation, bypassing SwiftUI's layout system entirely.

### What to Prototype First

Build a minimal proof-of-concept: 32 rows of `CATextLayer`, each with 33 monospaced JetBrains Mono characters, and a simple cascade animation that replaces all rows top-to-bottom over 500ms. This validates the rendering approach, confirms performance headroom, and provides a visceral feel for transitions at 60 FPS.

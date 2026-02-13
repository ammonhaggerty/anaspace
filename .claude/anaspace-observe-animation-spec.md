# Anaspace — Observe Animation Prototype Spec

## Purpose

Build a standalone prototype that validates the observe animation on a 33×32 character grid. Pressing a center button triggers a 10-second looping animation combining outbound "sonar" pulses with simulated inbound audio-reactive waves. The two wave systems create visual interference where they overlap.

---

## Grid Setup

- **Grid:** 33 columns × 32 rows of JetBrains Mono characters
- **Font size:** 15.52pt, letter spacing 11%, line height 22.3pt
- **Background color:** `#CBB4A5`
- **Rendering:** Each row per layer is a single `CATextLayer` (96 total: 32 rows × 3 layers)
- **All animation occurs on the transition layer (top layer).** Structure and content layers are empty for this prototype.
- **Origin point:** Bottom center of the grid (column 16, row 31). All distance calculations radiate from this point.

---

## Color Palette for This Animation

| Role | Color | Hex |
|------|-------|-----|
| Background | Warm tan | `#CBB4A5` |
| Outbound wave — primary | Dark brown | `#301818` |
| Outbound wave — secondary | Light warm | `#E4D7CE` |
| Outbound wave — accent | Red (very sparse) | `#FF0000` |
| Inbound wave | White | `#FFFFFF` |

### Color Distribution Within Outbound Waves

The outbound wave is not a single color. Across the 9-row band:

- **Leading edge (rows 1–2 of the band):** Predominantly `#E4D7CE` (light). Sparse glyphs fading in. The wave is arriving.
- **Core (rows 3–7 of the band):** Predominantly `#301818` (dark). Dense glyphs at the center. This is the body of the wave.
- **Trailing edge (rows 8–9 of the band):** Predominantly `#E4D7CE` (light), fading out. The wave is departing.
- **Red accent (`#FF0000`):** Used on 1–3 glyphs per wave per frame, randomly placed within the core zone. These should feel like occasional sparks — not a pattern, not predictable. They add a subtle living heat to the wave without creating a visible red band.

---

## Outbound Wave System ("Sonar")

### Wave Shape

Each outbound pulse is a radial band emanating from the origin point. Because the origin is at bottom-center rather than true center, the rings are semicircular arcs that expand upward and to the sides.

**Distance calculation:** For each cell (col, row), compute the Euclidean distance from the origin (16, 31):

```
distance = sqrt((col - 16)² + (row - 31)²)
```

This distance determines which part of the wave (if any) affects that cell at any given moment.

### Wave Parameters

| Parameter | Value |
|-----------|-------|
| Wave band width | 9 units (distance units, mapping roughly to rows at center) |
| Wave speed | Full grid traversal in ~2 seconds |
| Pulse frequency | ~1 Hz (new wave emitted every ~1 second) |
| Visible waves at once | ~2 (one mid-screen, one near edges) |
| Maximum distance | ~35 units (corner of grid from origin) |

### Wave Motion

Each wave has a `wavefront` value that increases over time, representing the distance of the wave's center from the origin:

```
wavefront = (elapsed_time × speed) mod max_cycle_distance
```

Where:
- `speed` ≈ 17.5 distance units per second (traverses ~35 units in 2 seconds)
- `max_cycle_distance` ≈ 35 + 9 (wave fully exits the grid before recycling)

A new wave begins when the previous wave's center is ~17.5 units out (1 second later), so two waves are always in flight.

### Cell Inclusion and Density

For each cell, calculate its position relative to the wave's center:

```
offset = distance_from_origin - wavefront
```

If `offset` is within the band range (–4.5 to +4.5 for a 9-unit band), the cell is part of this wave. The `offset` value determines the density tier:

| Offset from wave center | Band position | Density tier | Glyph weight |
|------------------------|---------------|-------------|--------------|
| –4.5 to –3.5 | Leading edge (far) | Tier 1 (minimal) | 30% fill chance |
| –3.5 to –2.0 | Leading edge (near) | Tier 2 (light) | 60% fill chance |
| –2.0 to +2.0 | Core | Tier 4–5 (heavy/solid) | 95% fill chance |
| +2.0 to +3.5 | Trailing edge (near) | Tier 2 (light) | 60% fill chance |
| +3.5 to +4.5 | Trailing edge (far) | Tier 1 (minimal) | 30% fill chance |

The **fill chance** means not every cell in the band gets a glyph. At the edges, 70% of cells are empty, creating a ragged, organic boundary. At the core, nearly all cells are filled, creating a solid mass.

### Glyph Selection

Each density tier has a pool of candidate glyphs. On each frame, when a cell needs a glyph, one is selected from the appropriate tier's pool.

**Chaos parameter (0.0 – 1.0):** Controls how much glyphs change frame-to-frame within the wave.

- **Chaos = 0.0:** Each cell picks a glyph once when the wave first reaches it and keeps that glyph until the wave passes. The wave looks like a solid, stable band sliding across the screen.
- **Chaos = 0.5:** Each cell has a 50% chance of re-randomizing its glyph each frame. The wave shimmers and shifts but retains a recognizable texture.
- **Chaos = 1.0:** Every cell re-randomizes every frame. The wave is a roiling, turbulent mass of changing characters.

**Recommended starting value: 0.3–0.4.** Enough movement to feel alive, not so much that it feels noisy.

Implementation: assign each cell a stable random seed when the wave first reaches it. Each frame, generate a random value from that seed + frame number. If the value is below the chaos threshold, pick a new glyph from the tier pool. Otherwise, keep the current one.

### Suggested Glyph Pools by Density Tier

These are starting points — refine by visual testing:

```
Tier 1 (minimal):  · ˙ ' ` , . ˑ ‧
Tier 2 (light):    - ~ ° ˜ ¯ ˉ ⁻ ₋ – ·
Tier 3 (medium):   + * # × ÷ = ≡ ╬ ┼ ╪ ╫ ░
Tier 4 (heavy):    ▒ ▓ ╬ ╠ ╣ ╦ ╩ ┃ ━ ┏ ┓ ┗ ┛ ▐ ▌
Tier 5 (solid):    █ ▇ ▆ ▉ ▊ ▋ ▍ ▎
```

All glyphs must be verified against JetBrains Mono's actual glyph set before implementation. The above is a conceptual starting point.

---

## Inbound Wave System (Audio Reactive)

### Concept

Inbound waves represent the audio the app is "hearing." They originate from the edges of the grid and move inward toward the origin point. Their density (visual intensity) correlates with audio amplitude.

For this prototype, audio amplitude is **simulated** with a pre-defined curve that creates realistic-feeling spikes and lulls over 10 seconds.

### Wave Parameters

| Parameter | Value |
|-----------|-------|
| Wave band width | 5 units (distance units) |
| Wave speed | ~2× outbound speed (~35 units per second, full traversal in ~1 second) |
| Direction | Inward — from max distance toward origin |
| Color | `#FFFFFF` (white) |
| Simultaneous waves | 1–2 visible at a time |
| Spawn rate | Amplitude-dependent (see below) |

### Wave Motion

Inbound waves start at the far edges of the grid (distance ~35 from origin) and move toward the origin:

```
wavefront = max_distance - (elapsed_since_spawn × speed)
```

When the wavefront reaches the origin (distance ≈ 0), the wave is consumed and disappears.

### Amplitude-Driven Behavior

A simulated amplitude value (0.0 – 1.0) drives three properties of the inbound waves:

**1. Density tier selection:**

| Amplitude range | Max density tier used | Visual result |
|----------------|----------------------|---------------|
| 0.0 – 0.2 | Tier 1 only | Faint wisps at edges |
| 0.2 – 0.4 | Tiers 1–2 | Light scattered marks |
| 0.4 – 0.6 | Tiers 1–3 | Moderate texture |
| 0.6 – 0.8 | Tiers 1–4 | Heavy, visible waves |
| 0.8 – 1.0 | Tiers 1–5 | Dense, solid waves |

**2. Penetration depth:** Low amplitude waves may spawn but fade out before reaching the center. High amplitude waves push all the way to the origin.

```
effective_range = amplitude × max_distance
```

A wave at amplitude 0.3 only reaches ~10 distance units from the edge before fading. At amplitude 1.0 it reaches the origin.

**3. Wave spawn rate:** Higher amplitude spawns waves more frequently.

| Amplitude range | Spawn interval |
|----------------|---------------|
| 0.0 – 0.3 | Every ~2 seconds (sparse) |
| 0.3 – 0.6 | Every ~1 second |
| 0.6 – 0.8 | Every ~0.6 seconds |
| 0.8 – 1.0 | Every ~0.3 seconds (rapid pulses) |

### Simulated Audio Curve (10-Second Test)

Pre-defined amplitude values to simulate a realistic audio input pattern. This should feel like music is playing with natural dynamics — not a steady tone.

```
Time (s)   Amplitude   What it represents
0.0–1.0    0.05–0.15   Quiet — app just started listening
1.0–1.5    0.15→0.55   Music fading in
1.5–3.0    0.45–0.65   Moderate music playing (slight variation)
3.0–3.3    0.65→0.90   Loud moment — chorus/beat drop
3.3–4.0    0.90→0.50   Settling back down
4.0–5.5    0.40–0.60   Steady mid-level (gentle oscillation)
5.5–6.0    0.60→0.30   Brief quiet passage
6.0–6.5    0.30→0.85   Builds back up
6.5–8.0    0.70–0.85   Sustained high energy
8.0–8.5    0.85→0.95   Peak — "signal found" moment
8.5–9.5    0.95→0.40   Rapid falloff as recognition resolves
9.5–10.0   0.40→0.10   Final fade
```

Interpolate smoothly between these keyframes. Apply a small amount of noise (±0.05) on top for organic jitter.

### Inbound Wave Band Profile

Similar to outbound but narrower (5 units):

| Offset from wave center | Density tier | Fill chance |
|------------------------|-------------|-------------|
| –2.5 to –1.5 | Tier 1 | 25% fill (modified by amplitude) |
| –1.5 to –0.5 | Tier 2–3 | 50% fill (modified by amplitude) |
| –0.5 to +0.5 | Max tier (amplitude-driven) | 80% fill |
| +0.5 to +1.5 | Tier 2–3 | 50% fill (modified by amplitude) |
| +1.5 to +2.5 | Tier 1 | 25% fill |

All fill chances are multiplied by the current amplitude value. At amplitude 0.2, even the core has only 16% fill chance (0.8 × 0.2), making the wave nearly invisible.

---

## Interference (Wave Crossing)

When an outbound wave and an inbound wave occupy the same cell simultaneously, a third visual behavior occurs. Neither wave "wins" — instead, the collision produces a distinct effect.

### Interference Rules

**Glyph transformation:** When both waves claim the same cell, the glyph is drawn from a special **interference pool** instead of either wave's normal density pool. These should be visually distinct — geometric, angular, or structurally different from the organic wave glyphs.

Suggested interference glyphs (verify against JetBrains Mono):
```
╳ ◊ ◆ ⬡ ⬢ ✦ ✧ ⊕ ⊗ ⊘ ⊙ ◉ ○ ● ◌ ◍ ◎
```

**Color:** Interference cells use the outbound wave's dark color (`#301818`) — the white inbound wave is "absorbed" by the collision, creating the impression that the outbound wave momentarily transforms rather than the inbound wave pushing through.

Alternatively (worth testing both):
- Use `#FFFFFF` (white wins) — creates bright flashes at collision points
- Alternate between dark and white per-cell randomly — creates a flickering/sparking effect at the interference boundary

**Density:** Interference cells are always high density (Tier 4–5). Collisions are visually intense regardless of either wave's individual density at that point.

**Chaos boost:** The chaos parameter should be temporarily boosted to 0.8–1.0 for interference cells. Collisions feel energetic and unstable — glyphs change rapidly even if the base chaos setting is low.

### Interference Zone Shape

The interference zone is wherever both waves' band ranges overlap. Because the outbound band is 9 units wide and the inbound band is 5 units wide, the overlap zone can be up to 5 units wide (when centered on each other) but is typically 2–4 units wide as the waves pass through each other.

The zone exists briefly — since the inbound wave moves at 2× speed, the crossing takes roughly 0.3–0.5 seconds for the bands to fully pass through each other. This is fast enough to feel like a collision, not a sustained overlay.

---

## Animation Lifecycle

### Trigger

User taps the center button.

### Startup (0–0.5s)

- First outbound wave spawns from origin
- No inbound activity yet (simulated amplitude is near zero)
- The outbound wave is the first thing the user sees — a ring of dark characters expanding upward from the button

### Active Loop (0.5–8.5s)

- Outbound waves pulse at ~1 Hz
- Inbound waves spawn based on the simulated amplitude curve
- Interference effects occur wherever waves cross
- The overall visual rhythm is: outbound pulse expands... inbound waves wash in from edges (with varying intensity)... brief interference flashes where they meet... outbound wave continues past... cycle repeats

### Resolution (8.5–10.0s)

- Simulated amplitude peaks then drops sharply
- Final inbound waves are the densest, pushing deep toward center
- Outbound waves continue their rhythm
- At t=10.0s, all waves rapidly converge to center (both outbound and inbound accelerate toward origin), creating a brief implosion effect
- Transition layer then clears completely (all cells empty), revealing whatever is beneath

### Post-Animation

- All transition layer cells are empty
- Grid returns to passive state
- Button returns to its default appearance

---

## Frame-by-Frame Computation

At 60 FPS, each frame the system must:

1. **Update wave positions:** Advance all active wave fronts (outbound and inbound) by their per-frame delta
2. **Sample amplitude:** Read current value from the simulated curve (interpolated)
3. **For each cell (col, row):**
   a. Compute distance from origin
   b. Check if cell falls within any outbound wave band → compute density tier and fill chance
   c. Check if cell falls within any inbound wave band → compute density tier and fill chance (amplitude-modified)
   d. If both → apply interference rules instead
   e. If one → select glyph from appropriate pool, apply chaos, assign color
   f. If neither → cell is empty
4. **Build row strings:** For each row, compose the 33-character attributed string with per-character glyphs and colors
5. **Update dirty rows:** Only update `CATextLayer` instances for rows that changed since last frame

### Expected Per-Frame Cost

- Wave position updates: trivial (2–4 floating point additions)
- Cell evaluation: 1,056 cells × (distance calc + band check) — simple arithmetic, well under 1ms
- Row string composition: ~6–10 rows will have changed content per frame (the wave bands span ~9 + ~5 rows, with some overlap)
- `CATextLayer` updates: 6–10 string mutations per frame

Total: well within the 16.6ms budget at 60 FPS.

---

## Configurable Parameters (For Tuning)

These should be exposed as adjustable values during prototyping:

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `outboundSpeed` | 17.5 units/s | 10–30 | How fast outbound waves expand |
| `outboundBandWidth` | 9 units | 5–15 | Thickness of outbound wave band |
| `outboundPulseInterval` | 1.0s | 0.5–2.0 | Time between new outbound pulses |
| `inboundSpeed` | 35 units/s | 20–50 | How fast inbound waves contract |
| `inboundBandWidth` | 5 units | 3–9 | Thickness of inbound wave band |
| `chaosAmount` | 0.35 | 0.0–1.0 | Glyph re-randomization rate |
| `interferenceChaos` | 0.85 | 0.0–1.0 | Chaos boost during interference |
| `redAccentFrequency` | 0.003 | 0.0–0.02 | Probability of red glyph per cell per frame in outbound core |
| `amplitudeSmoothing` | 0.15 | 0.0–0.5 | How much the amplitude signal is smoothed |
| `leadingEdgeFillChance` | 0.30 | 0.1–0.6 | Sparseness of wave edges |
| `coreFillChance` | 0.95 | 0.8–1.0 | Density of wave center |

Expose these as sliders in the prototype UI (outside the grid, perhaps in a debug panel toggled by a gesture).

---

## Prototype Deliverables

1. **A full-screen grid view** rendering 33×32 cells of JetBrains Mono on the `#CBB4A5` background
2. **A center button** below the grid that triggers the 10-second animation
3. **The outbound wave system** with correct radial propagation, density falloff, color distribution, and looping
4. **The inbound wave system** driven by the simulated amplitude curve
5. **Interference rendering** where waves overlap
6. **A debug panel** with sliders for all configurable parameters listed above
7. **FPS counter** displayed during animation to validate performance

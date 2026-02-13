# Anaspace — Core Concepts

## What It Is

A cultural exploration app that reveals the hidden connections between music, places, and moments in time. You hear a song, you're in a place, and Anaspace shows you the web of influences that shaped both — and lets you navigate that web in any direction.

---

## The Persistent Triad

Every view in Anaspace is anchored by three co-equal dimensions:

- **Subject** — a person, genre, movement, or work
- **Place** — a city, neighborhood, venue, or region
- **Time** — a year, decade, or era

All three are always present. The content shown is determined by the intersection of all three. When any one changes, the system assesses whether the other two are still valid and adjusts intelligently.

### How the Triad Responds to Change

**Time shifts → Subject reassessed:**
If the year changes from 1971 to 2026, the system asks: Is Sly Stone still relevant/alive? If yes, keep. If not, who is the closest analog — someone working in a similar creative space in 2026? If set to 1930, who carries that energy in that era?

**Place shifts → Subject reassessed:**
If the place changes from Oakland to Berlin, the system asks: Is Sly Stone connected to Berlin? If not, who is the Sly Stone of Berlin — someone with similar genre, energy, cultural role — in the current time anchor?

**Subject shifts → Place and Time reassessed:**
If the subject changes from Sly Stone to Kraftwerk, the system asks: Is Oakland still relevant? (Probably not — shift to Düsseldorf.) Is 1971 still relevant? (Yes, they were active — keep, or adjust to their peak.)

### Analog Finding

When a dimension shift makes the current subject irrelevant, the system finds the "closest analog" by scoring candidates on:
- **Genre/movement overlap** — do they work in a similar creative space?
- **Era relevance** — were they active during the target time?
- **Place connection** — are they connected to the target location?
- **Influence lineage** — are they in the same influence chain as the original?

The analog isn't just "someone famous from that place and time" — it's the person who occupies the most similar cultural role.

---

## The Knowledge Graph

Anaspace builds a web of cultural entities and their relationships.

### Entity Types
- **Person** — musicians, artists, designers, activists, producers
- **Place** — cities, neighborhoods, venues, regions
- **Work** — songs, albums, paintings, films, buildings
- **Genre** — musical genres, art movements, design movements
- **Era** — decades, cultural periods
- **Event** — concerts, festivals, founding moments, movements
- **Culture** — movements, aesthetics, schools of thought

### Relationship Types (by narrative weight)

**Story Edges** (highest weight — always visible):
- Influenced by, born in, created, collaborated with

**Context Edges** (shown when relevant):
- Genre, member of, active in, lives in, originated in, signed to

**Discovery Edges** (shown on expansion):
- Similar to, subgenre of, related movement, same era

### Data Sources
- **Wikidata** — structured knowledge: influences (P737), genres (P136), birthplaces (P19), origins (P740), movements (P135), notable works (P800), Apple Music IDs (P6492)
- **Wikipedia** — summary extracts for narrative content
- **Apple Music / MusicKit** — editorial notes, genre classification, catalog metadata
- **ShazamKit** — song recognition (the entry point)

---

## The Narrative Model

Three layers, each progressively more expensive. Use the cheapest layer that works.

### Layer 1 — Static Labels (free, no computation)
Direct from data: "influenced by," "born in," "genre: funk"

### Layer 2 — Contextual Labels (computed from data, no AI)
Templates combining 2-3 data points:
- "{person} was born in {place} in {year}"
- "Influenced by {artist}'s work in the {decade}"
- "{place}: center of {movement} in the {decade}"
- "Collaborated with {person} on {work} ({year})"

### Layer 3 — Narrative Sentences (AI-generated, one sentence per navigation)
Fires only when the user navigates to a new space. Single evocative sentence grounded in facts. Never speculative. References real works, years, places.

**Examples:**
- Steve Roach → Tangerine Dream: *"Roach first encountered Tangerine Dream's Phaedra as a teenager in Southern California, and its oceanic synthesizer washes became the foundation of his own ambient practice."*
- Steve Roach → Tucson: *"Roach relocated to the Sonoran Desert outside Tucson in the early 1990s, building his Timeroom studio where the landscape's silence and vastness became inseparable from his compositions."*

### Narrative Data Waterfall (before calling AI)
1. Apple Music editorialNotes → use if exists
2. Wikipedia first-paragraph extract → use if covers connection
3. Structured data + template (Layer 2) → use if facts available
4. **Only then** → call AI for one-sentence narrative

---

## Observation

The primary entry point. Two modes:

**Observe with music:** Shazam identifies a song → system looks up the artist, genre, era → intersects with current location → builds the initial triad → populates the graph.

**Observe without music:** Location only → system finds cultural entities connected to this place → suggests a subject → builds the triad from place outward.

---

## Personalization

User preferences are inferred, not declared. No forms, no onboarding questionnaires.

**Affinity model:**
- Genre affinities (e.g., "funk": 0.9, "classical": 0.3)
- Era affinities (e.g., "1970s": 0.8, "2010s": 0.5)
- Category affinities (e.g., "music": 0.7, "fashion": 0.6)

**Sources of inference:**
- Apple Music listening history (with permission)
- What the user explores in Anaspace (observations, graph navigation)
- Implicit: what they linger on, what they skip

**Effect:** Same graph, different emphasis. Personalization drives which connections surface prominently — it's math on the graph, not AI reasoning.

---

## Sovereign Data

All user data stays on-device. Observations, preferences, exploration history, personal graph — none of it touches a server. The app can be marketed as a sovereign data product. Cultural knowledge (Wikidata, Wikipedia) is fetched as needed but contains nothing personal.

---

## Core Principles

1. **The LLM is a narrator, not a researcher.** Feed it structured facts, ask it to narrate. Never ask the model to "know" things.
2. **The graph is the product.** AI generates flavor text; the knowledge graph generates insight.
3. **Three dimensions, always.** Time, place, subject — never collapse to fewer than three.
4. **Cheapest layer that works.** Static label before template before AI. Most interactions need zero AI.
5. **Infer, don't ask.** Personalization emerges from behavior, not questionnaires.
6. **Bidirectional exploration.** Every entity is both a destination and a departure point.

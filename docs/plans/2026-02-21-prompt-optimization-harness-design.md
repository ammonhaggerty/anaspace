# Prompt Optimization Test Harness Design

## Goal

Reverse-engineer the most effective prompt structures and word choices for Apple's on-device Foundation Model (~3B params) by systematically testing variations and having Claude evaluate results.

## Problem

The on-device model is small and purpose-built for explainability. Query complexity and word choice dramatically affect answer quality. We've observed:
- "Which... was most popular" works; "Who is the most iconic" triggers refusals
- Simple one-line questions work; multi-sentence instructions cause hallucination
- Some location/year combos consistently fail (SF 1984, Kansas City 1952)
- ~40% of certain question types hit Apple's guardrails

We need a systematic way to find optimal phrasing for each of 7 question types.

## Architecture

Single-loop iterative harness, entirely on-device in the iOS app.

Three components:
1. **FM Runner** -- Sends questions to Apple's on-device model via existing `ask()`. Returns raw Q&A pairs.
2. **Claude Evaluator** -- Sends batched Q&A pairs to Anthropic API for scoring and pattern analysis. Returns structured evaluation + proposed prompt rewrites.
3. **Iteration Controller** -- Manages the seed-evaluate-iterate loop, tracks running log, enforces time limits, assembles final report.

```
Iteration Controller
  -> generates prompt variants (seed round: current templates; later: Claude's proposals)
  -> FM Runner executes them against location/year combos
  -> collects [PromptTestResult] array
  -> sends batch to Claude Evaluator
  -> Claude returns scores + analysis + proposed rewrites
  -> Controller logs round, starts next round with new prompts
  -> repeat until time limit or convergence
```

No production code paths are touched. The harness reuses `ask()` and the Claude API key.

## Data Model

```swift
struct PromptTestCase {
    let questionType: String      // "subject", "collaborator", "peer", "influence", etc.
    let promptTemplate: String    // Prompt text with {subject}/{place}/{year} placeholders
    let location: String
    let year: Int
    let subject: String?          // nil for "subject" type, filled for entity questions
}

struct PromptTestResult {
    let testCase: PromptTestCase
    let fmAnswer: String?         // nil = refusal/error
    let error: String?
    let latencyMs: Int
}

struct RoundResult {
    let roundNumber: Int
    let results: [PromptTestResult]
    let claudeEvaluation: String
    let proposedRewrites: [ProposedRewrite]
}

struct ProposedRewrite {
    let questionType: String
    let newTemplate: String
    let rationale: String
    let testAgainst: [(location: String, year: Int)]
}
```

## 7 Question Types

1. Best known music artist from {location} in {year}
2. Greatest influence of {artist}
3. Closest peer to {artist} in {year}
4. Artist who directly followed in the lineage/style of {artist}
5. Event most closely associated with {artist} in {year}
6. Most popular song from {artist} in {year}
7. Music movement most closely associated with {artist} in {year}

## Seed Test Set

5 location/year combos spanning difficulty:
- London, 1977 (easy -- strong associations)
- Detroit, 1965 (medium -- Motown era)
- San Francisco, 1984 (hard -- known weak spot)
- Kansas City, 1952 (hard -- smaller city, jazz era)
- Lagos, 1973 (international -- Fela Kuti / Afrobeat)

7 question types x 5 combos = 35 FM calls for seed round (~12 seconds).

## Claude Evaluator

Direct Anthropic API calls (not through ClaudeService's complex prompt machinery). Simple `sendToClaudeAPI(system:user:) -> String` helper.

**Evaluation prompt asks Claude to:**
- Score each answer: CORRECT / PARTIALLY_CORRECT / WRONG / REFUSAL
- Provide correct answer if wrong
- Identify what about the phrasing led to the result
- Analyze patterns across all answers
- Propose specific prompt rewrites as JSON with test cases to re-run

**Proposed rewrites returned as JSON:**
```json
[{"questionType": "...", "template": "...", "rationale": "...",
  "testAgainst": [{"location": "...", "year": ...}]}]
```

## Iteration Flow

1. Start timer (default 5 minutes)
2. Seed round: 35 FM calls
3. Batch evaluate via Claude
4. Log round results
5. While time remains AND Claude proposed rewrites:
   a. Run proposed rewrites (5-15 FM calls)
   b. Evaluate new batch with context from previous rounds
   c. Log results
6. Final Claude call: summarize all rounds, output recommended templates
7. Display report in-app

**Time budget:** Seed ~12s FM + ~5s Claude. Each iteration ~5-10s FM + ~5s eval. In 5 minutes: ~15-20 rounds.

**Convergence:** Stop early if Claude says no further rewrites or all types score CORRECT.

**Context accumulation:** Each eval call includes summary of previous rounds (not full history) to stay within token limits.

## Output

- **Real-time:** Xcode console progress (e.g., `[HARNESS] Round 2: 12/15 correct, 2 wrong, 1 refusal`)
- **Final:** Scrollable in-app text view with Claude's full report and recommended prompt templates

## Integration

- New method `runPromptOptimization()` on `FoundationModelService`
- Triggered from `#if DEBUG` task block in `AnaspaceApp.swift`
- Reuses existing `ask()` for FM calls
- Reuses existing API key for Claude eval calls
- No production code changes
- After optimization: manually update `entityQuestions` templates with winners

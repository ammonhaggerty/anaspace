# Prompt Optimization Test Harness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an on-device test harness that systematically tests prompt variations against Apple's Foundation Model, with Claude API evaluating results and proposing improvements.

**Architecture:** Single-loop iterative harness inside `FoundationModelService`. FM Runner reuses existing `ask()`. Claude Evaluator makes direct Anthropic API calls using the existing API key from `CLAUDE_API_KEY` in Info.plist. Iteration Controller orchestrates seed→evaluate→iterate rounds with a configurable time limit.

**Tech Stack:** Swift 6, FoundationModels framework, Anthropic Messages API (direct URLRequest), SwiftUI (minimal report view)

---

### Task 1: Data Model

**Files:**
- Create: `anaspace/Services/AI/PromptHarness.swift`

**Step 1: Create the data model types**

Create `anaspace/Services/AI/PromptHarness.swift` with the data types the harness needs. These are self-contained — no dependencies on other app types.

```swift
import Foundation

// MARK: - Prompt Harness Data Model

struct PromptTestCase: Sendable {
    let questionType: String      // "subject", "collaborator", "peer", "influence", "follower", "creation", "event", "movement"
    let promptTemplate: String    // Prompt text with {subject}, {place}, {year} placeholders
    let location: String
    let year: Int
    let subject: String?          // nil for "subject" question type, filled for entity questions

    /// Fill placeholders with actual values.
    func filledPrompt() -> String {
        promptTemplate
            .replacingOccurrences(of: "{subject}", with: subject ?? "UNKNOWN")
            .replacingOccurrences(of: "{place}", with: location)
            .replacingOccurrences(of: "{year}", with: String(year))
    }
}

struct PromptTestResult: Sendable {
    let testCase: PromptTestCase
    let fmAnswer: String?         // nil = refusal/error
    let error: String?            // error description if failed
    let latencyMs: Int
}

struct ProposedRewrite: Sendable {
    let questionType: String
    let template: String
    let rationale: String
    let testAgainst: [(location: String, year: Int)]
}

struct RoundResult: Sendable {
    let roundNumber: Int
    let results: [PromptTestResult]
    let claudeEvaluation: String  // Claude's full analysis text
    let proposedRewrites: [ProposedRewrite]
}
```

**Step 2: Build and verify no compiler errors**

Run: Build via XcodeBuildMCP `build_sim`
Expected: Build succeeds with no errors in PromptHarness.swift

**Step 3: Commit**

```
git add anaspace/Services/AI/PromptHarness.swift
git commit -m "Add prompt harness data model types"
```

---

### Task 2: Claude Evaluator

**Files:**
- Modify: `anaspace/Services/AI/PromptHarness.swift`

**Step 1: Add the Claude API helper**

Add a `ClaudeEvaluator` actor to `PromptHarness.swift` that makes direct HTTP calls to the Anthropic Messages API. It reads the API key from `Bundle.main.infoDictionary?["CLAUDE_API_KEY"]`. It does NOT depend on `ClaudeService` — it's a self-contained helper.

```swift
// MARK: - Claude Evaluator

actor ClaudeEvaluator {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let model = "claude-sonnet-4-20250514"

    private var apiKey: String? {
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
    }

    /// Send a system + user message to Claude and return the text response.
    func evaluate(system: String, user: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw HarnessError.noApiKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HarnessError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw HarnessError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        // Parse Anthropic response: { "content": [{ "type": "text", "text": "..." }] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw HarnessError.parseError
        }

        return text
    }
}

enum HarnessError: Error, CustomStringConvertible {
    case noApiKey
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case parseError

    var description: String {
        switch self {
        case .noApiKey: return "No CLAUDE_API_KEY found in Info.plist"
        case .invalidResponse: return "Invalid HTTP response"
        case .apiError(let code, let body): return "API error \(code): \(body)"
        case .parseError: return "Failed to parse Claude response"
        }
    }
}
```

**Step 2: Build and verify**

Run: Build via XcodeBuildMCP `build_sim`
Expected: Build succeeds

**Step 3: Commit**

```
git add anaspace/Services/AI/PromptHarness.swift
git commit -m "Add Claude evaluator for prompt harness"
```

---

### Task 3: Seed Data & Prompt Templates

**Files:**
- Modify: `anaspace/Services/AI/PromptHarness.swift`

**Step 1: Add seed locations, years, and initial prompt templates**

Add constants for the seed test matrix and the current prompt templates (copied from `FoundationModelService.swift:126-135`). These are the starting point that Claude will iterate on.

```swift
// MARK: - Seed Data

struct HarnessSeedData {
    /// 20 locations spanning major cities, smaller cities, and international
    static let locations = [
        // Major US cities
        "New York City", "Los Angeles", "Chicago",
        // Medium US cities
        "San Francisco", "Detroit", "Nashville", "New Orleans", "Seattle", "Austin", "Memphis",
        // Smaller / harder US cities
        "Kansas City", "Minneapolis", "Portland",
        // International major
        "London", "Tokyo", "Lagos", "Berlin", "Paris",
        // International smaller
        "Kingston", "Havana"
    ]

    /// 10 years spanning 1926-2026
    static let years = [1932, 1947, 1955, 1965, 1973, 1977, 1984, 1992, 2005, 2020]

    /// Seed location/year combos for the first round (5 diverse pairs)
    static let seedCombos: [(location: String, year: Int)] = [
        ("London", 1977),
        ("Detroit", 1965),
        ("San Francisco", 1984),
        ("Kansas City", 1955),
        ("Lagos", 1973),
    ]

    /// Current prompt templates — the baseline we're optimizing from.
    /// Keyed by question type. Use {subject}, {place}, {year} placeholders.
    static let baselineTemplates: [(questionType: String, template: String)] = [
        ("subject", "Which music artist FROM {place} was most popular in {year}? Answer with just the name."),
        ("influence", "{subject}'s biggest musical influence? Answer with ONLY the name."),
        ("peer", "A musical peer of {subject} in {place} around {year}? Answer with ONLY the name."),
        ("follower", "An artist most directly influenced by {subject}? Answer with ONLY the name."),
        ("event", "A major music event in {place} around {year} connected to {subject}? Answer with ONLY the event name."),
        ("creation", "{subject}'s most famous song or album around {year}? Answer with ONLY the title."),
        ("movement", "The music genre or movement {subject} was part of in {year}? Answer with ONLY the genre name."),
    ]
}
```

**Step 2: Build and verify**

Run: Build via XcodeBuildMCP `build_sim`
Expected: Build succeeds

**Step 3: Commit**

```
git add anaspace/Services/AI/PromptHarness.swift
git commit -m "Add seed data and baseline templates for prompt harness"
```

---

### Task 4: Iteration Controller

**Files:**
- Modify: `anaspace/Services/AI/PromptHarness.swift`
- Modify: `anaspace/Services/AI/FoundationModelService.swift`

This is the core logic. The controller runs the seed→evaluate→iterate loop.

**Step 1: Add the PromptHarness class**

Add the main harness class to `PromptHarness.swift`. It takes a reference to `FoundationModelService.ask()` (via a closure) so it can call the on-device model without coupling to the service's internals.

```swift
// MARK: - Prompt Harness Controller

@MainActor
final class PromptHarness {
    private let askFM: (String) async -> String?
    private let evaluator = ClaudeEvaluator()
    private var rounds: [RoundResult] = []
    private(set) var report: String = ""
    private(set) var isRunning = false

    /// Initialize with a closure that calls the on-device Foundation Model.
    /// This decouples the harness from FoundationModelService internals.
    init(askFM: @escaping (String) async -> String?) {
        self.askFM = askFM
    }

    /// Run the full optimization loop. Returns the final report.
    func run(timeLimitSeconds: TimeInterval = 300) async -> String {
        isRunning = true
        rounds = []
        report = ""
        let deadline = Date.now.addingTimeInterval(timeLimitSeconds)

        print("[HARNESS] Starting prompt optimization (time limit: \(Int(timeLimitSeconds))s)")

        // --- Seed Round ---
        let seedResults = await runSeedRound()
        let seedEval = await evaluateRound(roundNumber: 1, results: seedResults, previousSummary: nil)
        rounds.append(seedEval)
        logRoundSummary(seedEval)

        // --- Iteration Rounds ---
        var roundNumber = 2
        while Date.now < deadline {
            guard let lastRound = rounds.last, !lastRound.proposedRewrites.isEmpty else {
                print("[HARNESS] No more rewrites proposed — converged.")
                break
            }

            let iterResults = await runRewrites(lastRound.proposedRewrites)
            if iterResults.isEmpty { break }

            let previousSummary = buildPreviousSummary()
            let iterEval = await evaluateRound(roundNumber: roundNumber, results: iterResults, previousSummary: previousSummary)
            rounds.append(iterEval)
            logRoundSummary(iterEval)

            roundNumber += 1
        }

        // --- Final Report ---
        report = await generateFinalReport()
        print("[HARNESS] === FINAL REPORT ===")
        print(report)
        print("[HARNESS] === END REPORT ===")

        isRunning = false
        return report
    }

    // MARK: - Seed Round

    private func runSeedRound() async -> [PromptTestResult] {
        print("[HARNESS] Running seed round...")
        var results: [PromptTestResult] = []

        // First pass: resolve subjects for each location/year combo
        var resolvedSubjects: [String: String] = [:] // "location|year" -> subject
        let subjectTemplate = HarnessSeedData.baselineTemplates.first { $0.questionType == "subject" }!.template

        for combo in HarnessSeedData.seedCombos {
            let testCase = PromptTestCase(
                questionType: "subject",
                promptTemplate: subjectTemplate,
                location: combo.location,
                year: combo.year,
                subject: nil
            )
            let result = await runSingleTest(testCase)
            results.append(result)

            if let answer = result.fmAnswer {
                resolvedSubjects["\(combo.location)|\(combo.year)"] = answer
            }
        }

        // Second pass: entity questions using resolved subjects
        let entityTemplates = HarnessSeedData.baselineTemplates.filter { $0.questionType != "subject" }

        for combo in HarnessSeedData.seedCombos {
            guard let subject = resolvedSubjects["\(combo.location)|\(combo.year)"] else { continue }

            for template in entityTemplates {
                let testCase = PromptTestCase(
                    questionType: template.questionType,
                    promptTemplate: template.template,
                    location: combo.location,
                    year: combo.year,
                    subject: subject
                )
                let result = await runSingleTest(testCase)
                results.append(result)
            }
        }

        print("[HARNESS] Seed round: \(results.count) tests completed")
        return results
    }

    // MARK: - Run Rewrites

    private func runRewrites(_ rewrites: [ProposedRewrite]) async -> [PromptTestResult] {
        var results: [PromptTestResult] = []

        for rewrite in rewrites {
            for combo in rewrite.testAgainst {
                // For subject rewrites, subject is nil
                // For entity rewrites, we need a subject — use the last known one or resolve fresh
                let subject: String?
                if rewrite.questionType == "subject" {
                    subject = nil
                } else {
                    // Try to resolve subject for this combo using the best known subject template
                    let subjectTemplate = HarnessSeedData.baselineTemplates.first { $0.questionType == "subject" }!.template
                    let subjectCase = PromptTestCase(
                        questionType: "subject", promptTemplate: subjectTemplate,
                        location: combo.location, year: combo.year, subject: nil
                    )
                    let subjectResult = await runSingleTest(subjectCase)
                    subject = subjectResult.fmAnswer
                    results.append(subjectResult)
                }

                let testCase = PromptTestCase(
                    questionType: rewrite.questionType,
                    promptTemplate: rewrite.template,
                    location: combo.location,
                    year: combo.year,
                    subject: subject
                )
                let result = await runSingleTest(testCase)
                results.append(result)
            }
        }

        print("[HARNESS] Rewrite round: \(results.count) tests completed")
        return results
    }

    // MARK: - Single Test Execution

    private func runSingleTest(_ testCase: PromptTestCase) async -> PromptTestResult {
        let prompt = testCase.filledPrompt()
        let start = CFAbsoluteTimeGetCurrent()
        let answer = await askFM(prompt)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        let error: String? = answer == nil ? "Refusal or empty response" : nil
        let label = answer ?? "REFUSAL"
        print("[HARNESS]   \(testCase.questionType)@\(testCase.location)-\(testCase.year): \(label) (\(elapsed)ms)")

        return PromptTestResult(
            testCase: testCase,
            fmAnswer: answer,
            error: error,
            latencyMs: elapsed
        )
    }

    // MARK: - Claude Evaluation

    private func evaluateRound(roundNumber: Int, results: [PromptTestResult], previousSummary: String?) async -> RoundResult {
        print("[HARNESS] Sending round \(roundNumber) to Claude for evaluation (\(results.count) results)...")

        let system = """
        You are evaluating answers from a small on-device language model (~3B params) about music culture. \
        For each answer, score it and explain why. Then analyze patterns across all answers to identify \
        what prompt phrasings work vs fail. The model responds best to simple, direct, factual questions. \
        It struggles with complex instructions, abstract concepts, and questions about less well-known \
        cultural combinations.
        """

        var user = "## Round \(roundNumber) Results\n\n"

        if let summary = previousSummary {
            user += "### Previous Rounds Summary\n\(summary)\n\n"
        }

        for (i, result) in results.enumerated() {
            user += """
            ### Test \(i + 1)
            Question type: \(result.testCase.questionType)
            Prompt template: "\(result.testCase.promptTemplate)"
            Filled prompt: "\(result.testCase.filledPrompt())"
            Location: \(result.testCase.location) | Year: \(result.testCase.year)\(result.testCase.subject.map { " | Subject: \($0)" } ?? "")
            FM Answer: \(result.fmAnswer.map { "\"\($0)\"" } ?? "REFUSAL/ERROR")\(result.error.map { " (Error: \($0))" } ?? "")
            Latency: \(result.latencyMs)ms


            """
        }

        user += """
        ## Instructions
        For each answer:
        1. Score: CORRECT / PARTIALLY_CORRECT / WRONG / REFUSAL
        2. If wrong, what would be a correct or acceptable answer?
        3. What about the prompt phrasing might have led to this result?

        Then provide:
        - PATTERNS: What phrasing patterns correlate with good/bad results?
        - WEAK_SPOTS: Which question types or location/year combos are failing?
        - PROPOSED_REWRITES: For each failing pattern, propose 1-2 specific prompt rewrites \
        with the exact template text (use {subject}, {place}, {year} placeholders). \
        Include which test cases to re-run them against. You may also propose NEW location/year \
        combos not in the seed set to probe specific hypotheses.

        IMPORTANT: End your response with a JSON block on its own line, starting with ```json and ending with ```:
        ```json
        [{"questionType": "...", "template": "...", "rationale": "...", "testAgainst": [{"location": "...", "year": ...}]}]
        ```
        If no rewrites are needed, return an empty array: []
        """

        do {
            let response = try await evaluator.evaluate(system: system, user: user)
            let rewrites = parseRewrites(from: response)

            return RoundResult(
                roundNumber: roundNumber,
                results: results,
                claudeEvaluation: response,
                proposedRewrites: rewrites
            )
        } catch {
            print("[HARNESS] Claude evaluation error: \(error)")
            return RoundResult(
                roundNumber: roundNumber,
                results: results,
                claudeEvaluation: "ERROR: \(error)",
                proposedRewrites: []
            )
        }
    }

    // MARK: - Parse Rewrites JSON

    private func parseRewrites(from response: String) -> [ProposedRewrite] {
        // Find JSON block between ```json and ```
        guard let jsonStart = response.range(of: "```json\n"),
              let jsonEnd = response.range(of: "\n```", range: jsonStart.upperBound..<response.endIndex) else {
            // Try without markdown fences — look for [ ... ] at the end
            if let bracketStart = response.lastIndex(of: "["),
               let bracketEnd = response.lastIndex(of: "]"),
               bracketStart < bracketEnd {
                let jsonStr = String(response[bracketStart...bracketEnd])
                return decodeRewrites(jsonStr)
            }
            print("[HARNESS] No JSON block found in Claude response")
            return []
        }

        let jsonStr = String(response[jsonStart.upperBound..<jsonEnd.lowerBound])
        return decodeRewrites(jsonStr)
    }

    private func decodeRewrites(_ jsonStr: String) -> [ProposedRewrite] {
        guard let data = jsonStr.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[HARNESS] Failed to parse rewrites JSON")
            return []
        }

        return array.compactMap { dict -> ProposedRewrite? in
            guard let questionType = dict["questionType"] as? String,
                  let template = dict["template"] as? String,
                  let rationale = dict["rationale"] as? String,
                  let testAgainst = dict["testAgainst"] as? [[String: Any]] else { return nil }

            let combos = testAgainst.compactMap { combo -> (location: String, year: Int)? in
                guard let loc = combo["location"] as? String,
                      let year = combo["year"] as? Int else { return nil }
                return (location: loc, year: year)
            }

            return ProposedRewrite(
                questionType: questionType,
                template: template,
                rationale: rationale,
                testAgainst: combos
            )
        }
    }

    // MARK: - Logging & Summary

    private func logRoundSummary(_ round: RoundResult) {
        let correct = round.results.filter { $0.fmAnswer != nil }.count
        let total = round.results.count
        let refusals = round.results.filter { $0.error != nil }.count
        print("[HARNESS] Round \(round.roundNumber): \(correct)/\(total) answered, \(refusals) refusals, \(round.proposedRewrites.count) rewrites proposed")
    }

    private func buildPreviousSummary() -> String {
        rounds.map { round in
            let correct = round.results.filter { $0.fmAnswer != nil }.count
            let total = round.results.count
            return "Round \(round.roundNumber): \(correct)/\(total) answered. Key findings: \(round.claudeEvaluation.prefix(200))..."
        }.joined(separator: "\n")
    }

    // MARK: - Final Report

    private func generateFinalReport() async -> String {
        print("[HARNESS] Generating final report...")

        let system = """
        You are summarizing a prompt optimization experiment for a small on-device language model (~3B params). \
        Review all rounds and provide a final report with recommended prompt templates.
        """

        var user = "## All Round Results\n\n"
        for round in rounds {
            user += "### Round \(round.roundNumber)\n"
            user += round.claudeEvaluation
            user += "\n\n---\n\n"
        }

        user += """
        ## Final Report Instructions
        Please provide:
        1. **Executive Summary**: 2-3 sentences on overall findings
        2. **Recommended Templates**: For each of the 7 question types (subject, influence, peer, follower, event, creation, movement), provide the single best prompt template found. Use {subject}, {place}, {year} placeholders.
        3. **Phrasing Rules**: General rules about what phrasings work/don't work with this model
        4. **Known Blind Spots**: Location/year combos or question types that remain unreliable
        5. **Confidence Level**: How confident are you in these recommendations (high/medium/low) and why
        """

        do {
            return try await evaluator.evaluate(system: system, user: user)
        } catch {
            return "ERROR generating final report: \(error)"
        }
    }
}
```

**Step 2: Expose `ask()` from FoundationModelService**

In `anaspace/Services/AI/FoundationModelService.swift`, the `ask()` method is currently `private`. We need to either make it accessible to the harness or provide a public wrapper. The cleanest approach: add a public method that creates a `PromptHarness` wired to `ask()`.

Add this method to `FoundationModelService` after the existing `runStructuredDiagnostic()` method (around line 102):

```swift
    /// Run the prompt optimization harness. Check Xcode console for progress, returns final report.
    func runPromptOptimization(timeLimitSeconds: TimeInterval = 300) async -> String {
        let harness = PromptHarness { [weak self] question in
            await self?.ask(question)
        }
        return await harness.run(timeLimitSeconds: timeLimitSeconds)
    }
```

**Step 3: Build and verify**

Run: Build via XcodeBuildMCP `build_sim`
Expected: Build succeeds

**Step 4: Commit**

```
git add anaspace/Services/AI/PromptHarness.swift anaspace/Services/AI/FoundationModelService.swift
git commit -m "Add iteration controller and wire harness to FoundationModelService"
```

---

### Task 5: Trigger & In-App Report View

**Files:**
- Modify: `anaspace/App/AnaspaceApp.swift`

**Step 1: Add the debug trigger and report view**

Add a `#if DEBUG` block that launches the harness on app start and displays results in a sheet. This goes in the `.task` modifier of `ContentView`, after the existing permission setup code.

In `AnaspaceApp.swift`, add a state variable near the other `@State` properties (around line 42):

```swift
    #if DEBUG
    @State private var harnessReport: String?
    @State private var isHarnessRunning = false
    #endif
```

In the `.task` block (currently around line 490-495), add after `onboardingRenderer.permissions = serviceManager.permissions`:

```swift
            #if DEBUG
            // Prompt optimization harness — check Xcode console for progress
            Task {
                isHarnessRunning = true
                try? await serviceManager.claude.activate()
                let report = await serviceManager.claude.runPromptOptimization(timeLimitSeconds: 300)
                harnessReport = report
                isHarnessRunning = false
            }
            #endif
```

Add a sheet modifier on the main view body (after the existing `.task` modifier):

```swift
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if isHarnessRunning {
                Text("HARNESS RUNNING...")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    .padding()
            }
        }
        .sheet(isPresented: Binding(
            get: { harnessReport != nil },
            set: { if !$0 { harnessReport = nil } }
        )) {
            if let report = harnessReport {
                NavigationStack {
                    ScrollView {
                        Text(report)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("Prompt Optimization Report")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { harnessReport = nil }
                        }
                    }
                }
            }
        }
        #endif
```

**Step 2: Build and verify**

Run: Build via XcodeBuildMCP `build_sim`
Expected: Build succeeds

**Step 3: Commit**

```
git add anaspace/App/AnaspaceApp.swift
git commit -m "Add debug trigger and report sheet for prompt harness"
```

---

### Task 6: Build, Run, and Verify

**Files:** None (testing only)

**Step 1: Build the app**

Run: Build via XcodeBuildMCP `build_sim`
Expected: Build succeeds

**Step 2: Launch on simulator with log capture**

Run: Launch via XcodeBuildMCP `launch_app_logs_sim`
Expected: App launches, console shows `[HARNESS] Starting prompt optimization...`

**Step 3: Wait ~60 seconds and check logs**

Wait for initial seed round + first evaluation. Check console for:
- `[HARNESS] Running seed round...` — FM queries executing
- `[HARNESS] subject@London-1977: David Bowie (280ms)` — individual test results
- `[HARNESS] Seed round: 35 tests completed` — seed round done
- `[HARNESS] Sending round 1 to Claude for evaluation...` — Claude API call
- `[HARNESS] Round 1: XX/35 answered, X refusals, X rewrites proposed` — round summary

**Step 4: Let it run the full 5 minutes**

The harness should iterate through multiple rounds. Watch for:
- Subsequent rounds with different prompt templates
- Claude identifying patterns and proposing rewrites
- Convergence (no more rewrites) or time limit reached
- `[HARNESS] === FINAL REPORT ===` at the end

**Step 5: Verify the in-app report**

When the harness finishes, a sheet should appear with the full Claude report. Verify:
- Report is readable and contains recommended templates
- Sheet dismisses with "Done" button

**Step 6: Commit (if any fixes were needed)**

If fixes were required during testing, commit them:
```
git add -u
git commit -m "Fix prompt harness issues found during testing"
```

---

### Task 7: Clean Up and Final Commit

**Files:**
- Modify: `anaspace/App/AnaspaceApp.swift` (optional)

**Step 1: Decide on trigger mechanism**

After verifying the harness works, consider whether the auto-launch in `.task` should be:
- Kept as-is (auto-runs on every debug launch) — fine for active development
- Gated behind a manual trigger (e.g., a hidden button or shake gesture) — better if you want the app to work normally in debug mode

For now, leave it as auto-launch since we're actively iterating. It can be commented out when not needed.

**Step 2: Commit any final changes**

```
git add -u
git commit -m "Prompt optimization harness ready for iteration"
```

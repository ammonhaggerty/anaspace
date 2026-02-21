#if DEBUG
import Foundation

// MARK: - Prompt Harness Data Model

/// A location + year pair used throughout the harness.
struct LocationYear: Sendable {
    let location: String
    let year: Int
}

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
    let testAgainst: [LocationYear]
}

struct RoundResult: Sendable {
    let roundNumber: Int
    let results: [PromptTestResult]
    let claudeEvaluation: String  // Claude's full analysis text
    let proposedRewrites: [ProposedRewrite]
}

// MARK: - Harness Error

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

// MARK: - Claude Evaluator

actor ClaudeEvaluator {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let model = "claude-sonnet-4-20250514"

    nonisolated private var apiKey: String? {
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
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw HarnessError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
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

    /// 10 years spanning 1932-2020
    static let years = [1932, 1947, 1955, 1965, 1973, 1977, 1984, 1992, 2005, 2020]

    /// Seed location/year combos for the first round (5 diverse pairs)
    static let seedCombos: [LocationYear] = [
        LocationYear(location: "London", year: 1977),
        LocationYear(location: "Detroit", year: 1965),
        LocationYear(location: "San Francisco", year: 1984),
        LocationYear(location: "Kansas City", year: 1955),
        LocationYear(location: "Lagos", year: 1973),
    ]

    /// Current prompt templates -- the baseline we're optimizing from.
    /// Keyed by question type. Use {subject}, {place}, {year} placeholders.
    static let baselineTemplates: [(questionType: String, template: String)] = [
        ("subject", "Which music artist FROM {place} was most popular in {year}? Answer with just the name."),
        ("collaborator", "{subject}'s closest musical collaborator around {year}? Answer with ONLY the name."),
        ("peer", "A musical peer of {subject} in {place} around {year}? Answer with ONLY the name."),
        ("influence", "{subject}'s biggest musical influence? Answer with ONLY the name."),
        ("follower", "An artist most directly influenced by {subject}? Answer with ONLY the name."),
        ("creation", "{subject}'s most famous song or album around {year}? Answer with ONLY the title."),
        ("place", "The venue in {place} most associated with {subject}? Answer with ONLY the venue name."),
        ("event", "A major music event in {place} around {year} connected to {subject}? Answer with ONLY the event name."),
        ("movement", "The music genre or movement {subject} was part of in {year}? Answer with ONLY the genre name."),
    ]
}

// MARK: - Prompt Harness Controller

@MainActor
final class PromptHarness {
    private let askFM: (String) async -> String?
    private let evaluator = ClaudeEvaluator()
    private var rounds: [RoundResult] = []
    private(set) var report: String = ""
    private(set) var isRunning = false

    init(askFM: @escaping (String) async -> String?) {
        self.askFM = askFM
    }

    func run(timeLimitSeconds: TimeInterval = 300) async -> String {
        isRunning = true
        rounds = []
        report = ""
        let deadline = Date.now.addingTimeInterval(timeLimitSeconds)

        print("[HARNESS] Starting prompt optimization (time limit: \(Int(timeLimitSeconds))s)")

        // Seed round
        let seedResults = await runSeedRound()
        let seedEval = await evaluateRound(roundNumber: 1, results: seedResults, previousSummary: nil)
        rounds.append(seedEval)
        logRoundSummary(seedEval)

        // Iteration rounds
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

        // Final report
        report = await generateFinalReport()
        print("[HARNESS] === FINAL REPORT ===")
        print(report)
        print("[HARNESS] === END REPORT ===")

        isRunning = false
        return report
    }

    // MARK: - Seed Round

    private func runSeedRound() async -> [PromptTestResult] {
        var results: [PromptTestResult] = []

        // Find the subject template
        guard let subjectEntry = HarnessSeedData.baselineTemplates.first(where: { $0.questionType == "subject" }) else {
            print("[HARNESS] ERROR: No 'subject' template found in baselineTemplates")
            return results
        }

        let nonSubjectTemplates = HarnessSeedData.baselineTemplates.filter { $0.questionType != "subject" }

        for combo in HarnessSeedData.seedCombos {
            print("[HARNESS] Seed: \(combo.location) \(combo.year)")

            // First resolve the subject
            let subjectCase = PromptTestCase(
                questionType: "subject",
                promptTemplate: subjectEntry.template,
                location: combo.location,
                year: combo.year,
                subject: nil
            )
            let subjectResult = await runSingleTest(subjectCase)
            results.append(subjectResult)

            let resolvedSubject = subjectResult.fmAnswer ?? "UNKNOWN"

            // Run all non-subject templates with the resolved subject
            for entry in nonSubjectTemplates {
                let testCase = PromptTestCase(
                    questionType: entry.questionType,
                    promptTemplate: entry.template,
                    location: combo.location,
                    year: combo.year,
                    subject: resolvedSubject
                )
                let result = await runSingleTest(testCase)
                results.append(result)
            }
        }

        return results
    }

    // MARK: - Run Rewrites

    private func runRewrites(_ rewrites: [ProposedRewrite]) async -> [PromptTestResult] {
        var results: [PromptTestResult] = []

        guard let subjectEntry = HarnessSeedData.baselineTemplates.first(where: { $0.questionType == "subject" }) else {
            print("[HARNESS] ERROR: No 'subject' template found in baselineTemplates")
            return results
        }

        for rewrite in rewrites {
            print("[HARNESS] Testing rewrite for '\(rewrite.questionType)': \(rewrite.rationale)")

            for locYear in rewrite.testAgainst {
                // Resolve subject first if this is not a subject-type rewrite
                let resolvedSubject: String?
                if rewrite.questionType == "subject" {
                    resolvedSubject = nil
                } else {
                    let subjectCase = PromptTestCase(
                        questionType: "subject",
                        promptTemplate: subjectEntry.template,
                        location: locYear.location,
                        year: locYear.year,
                        subject: nil
                    )
                    let subjectResult = await runSingleTest(subjectCase)
                    resolvedSubject = subjectResult.fmAnswer ?? "UNKNOWN"
                }

                let testCase = PromptTestCase(
                    questionType: rewrite.questionType,
                    promptTemplate: rewrite.template,
                    location: locYear.location,
                    year: locYear.year,
                    subject: resolvedSubject
                )
                let result = await runSingleTest(testCase)
                results.append(result)
            }
        }

        return results
    }

    // MARK: - Single Test Execution

    private func runSingleTest(_ testCase: PromptTestCase) async -> PromptTestResult {
        let filled = testCase.filledPrompt()
        let start = CFAbsoluteTimeGetCurrent()
        let answer = await askFM(filled)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let latencyMs = Int(elapsed * 1000)

        let displayAnswer = answer ?? "<REFUSAL/nil>"
        print("[HARNESS]   \(testCase.questionType)@\(testCase.location)-\(testCase.year): \(displayAnswer) (\(latencyMs)ms)")

        return PromptTestResult(
            testCase: testCase,
            fmAnswer: answer,
            error: answer == nil ? "refusal or error" : nil,
            latencyMs: latencyMs
        )
    }

    // MARK: - Evaluation

    private func evaluateRound(roundNumber: Int, results: [PromptTestResult], previousSummary: String?) async -> RoundResult {
        let systemPrompt = """
            You are evaluating the outputs of a small (~3B parameter) ON-DEVICE language model \
            that answers factual questions about music history. The model runs on iPhone via Apple's \
            FoundationModels framework. It has limited knowledge and often refuses or gives wrong answers.

            Your job:
            1. Score each answer: CORRECT, PARTIALLY_CORRECT, WRONG, or REFUSAL
            2. Identify patterns in failures (what phrasing works, what doesn't)
            3. Propose rewritten prompt templates that might improve results

            The model responds best to simple, direct factual questions. It struggles with:
            - Complex phrasing or multiple clauses
            - Obscure locations or time periods
            - Questions that require inference or reasoning

            For proposed rewrites, output a JSON array in a ```json fenced block.
            """

        var userMessage = "## Round \(roundNumber) Results\n\n"

        if let summary = previousSummary {
            userMessage += "### Previous Rounds Summary\n\(summary)\n\n"
        }

        userMessage += "### Test Results\n\n"

        for result in results {
            let tc = result.testCase
            userMessage += """
                - **Type**: \(tc.questionType)
                - **Template**: `\(tc.promptTemplate)`
                - **Filled**: `\(tc.filledPrompt())`
                - **Location**: \(tc.location), **Year**: \(tc.year)
                - **Subject**: \(tc.subject ?? "N/A")
                - **FM Answer**: \(result.fmAnswer ?? "<REFUSAL/nil>")
                - **Latency**: \(result.latencyMs)ms
                ---

                """
        }

        userMessage += """

            ### Instructions
            1. Score each result above as CORRECT, PARTIALLY_CORRECT, WRONG, or REFUSAL.
            2. Summarize patterns: which question types succeed, which fail, and why.
            3. Propose rewritten templates as a JSON array in a ```json block:
            ```json
            [
              {
                "questionType": "...",
                "template": "...",
                "rationale": "...",
                "testAgainst": [{"location": "...", "year": ...}]
              }
            ]
            ```
            Only propose rewrites for templates that need improvement. Use {subject}, {place}, {year} placeholders.
            Include 2-3 diverse test locations in testAgainst for each rewrite.
            """

        var claudeResponse: String
        do {
            claudeResponse = try await evaluator.evaluate(system: systemPrompt, user: userMessage)
        } catch {
            print("[HARNESS] Claude evaluation error: \(error)")
            claudeResponse = "Evaluation failed: \(error)"
        }

        let rewrites = parseRewrites(from: claudeResponse)

        return RoundResult(
            roundNumber: roundNumber,
            results: results,
            claudeEvaluation: claudeResponse,
            proposedRewrites: rewrites
        )
    }

    // MARK: - Parse Rewrites

    private func parseRewrites(from response: String) -> [ProposedRewrite] {
        // Try to find JSON in ```json fenced block first
        var jsonString: String?

        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fallback: find last [...] in the response
        if jsonString == nil {
            if let lastOpen = response.range(of: "[", options: .backwards),
               let lastClose = response.range(of: "]", options: .backwards),
               lastOpen.lowerBound < lastClose.lowerBound {
                jsonString = String(response[lastOpen.lowerBound...lastClose.lowerBound])
            }
        }

        guard let json = jsonString,
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[HARNESS] Could not parse rewrites JSON")
            return []
        }

        var rewrites: [ProposedRewrite] = []
        for item in array {
            guard let questionType = item["questionType"] as? String,
                  let template = item["template"] as? String,
                  let rationale = item["rationale"] as? String else {
                continue
            }

            var testLocations: [LocationYear] = []
            if let testAgainst = item["testAgainst"] as? [[String: Any]] {
                for loc in testAgainst {
                    if let location = loc["location"] as? String,
                       let year = loc["year"] as? Int {
                        testLocations.append(LocationYear(location: location, year: year))
                    }
                }
            }

            // Default test locations if none provided
            if testLocations.isEmpty {
                testLocations = [
                    LocationYear(location: "New York City", year: 1973),
                    LocationYear(location: "London", year: 1977),
                ]
            }

            rewrites.append(ProposedRewrite(
                questionType: questionType,
                template: template,
                rationale: rationale,
                testAgainst: testLocations
            ))
        }

        print("[HARNESS] Parsed \(rewrites.count) proposed rewrites")
        return rewrites
    }

    // MARK: - Logging & Summaries

    private func logRoundSummary(_ round: RoundResult) {
        let answered = round.results.filter { $0.fmAnswer != nil }.count
        let refusals = round.results.filter { $0.fmAnswer == nil }.count
        let total = round.results.count
        let rewriteCount = round.proposedRewrites.count

        print("[HARNESS] Round \(round.roundNumber): \(answered)/\(total) answered, \(refusals) refusals, \(rewriteCount) rewrites proposed")
    }

    private func buildPreviousSummary() -> String {
        var summary = ""
        for round in rounds {
            let answered = round.results.filter { $0.fmAnswer != nil }.count
            let total = round.results.count
            let evalPreview = String(round.claudeEvaluation.prefix(200))
            summary += "**Round \(round.roundNumber)**: \(answered)/\(total) answered. "
            summary += "Eval: \(evalPreview)...\n\n"
        }
        return summary
    }

    // MARK: - Final Report

    private func generateFinalReport() async -> String {
        let systemPrompt = """
            You are producing the final report for a prompt optimization session targeting a small \
            (~3B parameter) on-device language model for music history questions. Summarize the findings \
            clearly and actionably.
            """

        var userMessage = "## All Round Evaluations\n\n"
        for round in rounds {
            let answered = round.results.filter { $0.fmAnswer != nil }.count
            let total = round.results.count
            userMessage += "### Round \(round.roundNumber) (\(answered)/\(total) answered)\n"
            userMessage += round.claudeEvaluation
            userMessage += "\n\n---\n\n"
        }

        userMessage += """

            ### Produce a Final Report with:
            1. **Executive Summary**: 2-3 sentences on overall findings
            2. **Recommended Templates**: Best prompt template for each of these 9 question types: \
            subject, collaborator, peer, influence, follower, creation, place, event, movement. \
            Use {subject}, {place}, {year} placeholders.
            3. **Phrasing Rules**: General rules for how to phrase questions for this model
            4. **Known Blind Spots**: Locations, time periods, or question types the model struggles with
            5. **Confidence Level**: Your confidence (HIGH/MEDIUM/LOW) in the recommended templates
            """

        do {
            return try await evaluator.evaluate(system: systemPrompt, user: userMessage)
        } catch {
            print("[HARNESS] Final report generation failed: \(error)")
            return "Final report generation failed: \(error)"
        }
    }
}
#endif

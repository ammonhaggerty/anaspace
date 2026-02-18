import UIKit

// MARK: - Configuration

extension ObserveAnimation {

    struct Config {
        var outboundSpeed: Float = 8.75         // distance units per second
        var outboundBandWidth: Float = 9.0     // distance units
        var outboundPulseInterval: Float = 2.0 // seconds between pulses
        var inboundSpeed: Float = 35.0         // distance units per second
        var inboundBandWidth: Float = 5.0      // distance units
        var chaos: Float = 0.08                 // glyph re-randomization rate (low = persistent)
        var interferenceChaos: Float = 0.85    // chaos boost during interference
        var redAccentChance: Float = 0.003     // per-cell per-frame red chance
        var duration: Float = 10.0             // total animation seconds
        var isIndefinite: Bool = false          // loop forever (no auto-stop)
        var skipRows: Set<Int> = []            // rows to leave clear (e.g., header)
        var isEvaluating: Bool = false         // contracting circles mode
        var inboundEnabled: Bool = false       // spawn inbound waves
    }
}

// MARK: - Wave Types

private struct OutboundWave {
    var spawnTime: Float
}

private struct InboundWave {
    var spawnTime: Float
    var amplitude: Float   // amplitude at spawn time
}

// MARK: - Glyph Pools

private let tier1Glyphs: [Character] = Array("\u{00B7}\u{02D9}'\u{0060},.")
private let tier2Glyphs: [Character] = Array("-~\u{00B0}\u{00AF}\u{2013}\u{00B7}")
private let tier3Glyphs: [Character] = Array("+*#\u{00D7}=\u{2591}\u{253C}")
private let tier4Glyphs: [Character] = Array("\u{2592}\u{2593}\u{256C}\u{2560}\u{2563}\u{2501}\u{2590}\u{258C}")
private let tier5Glyphs: [Character] = Array("\u{2588}\u{2587}\u{2586}\u{2589}\u{258A}\u{258B}\u{258D}\u{258E}")
private let interferenceGlyphs: [Character] = Array("\u{2573}\u{25C6}\u{25CF}\u{25CB}\u{25C9}\u{2295}\u{2297}\u{25CA}")

private let allTiers: [[Character]] = [tier1Glyphs, tier2Glyphs, tier3Glyphs, tier4Glyphs, tier5Glyphs]

// MARK: - Amplitude Keyframes

private let amplitudeKeyframes: [(time: Float, value: Float)] = [
    (0.0, 0.05), (1.0, 0.15), (1.5, 0.55), (3.0, 0.65),
    (3.3, 0.90), (4.0, 0.50), (5.5, 0.60), (6.0, 0.30),
    (6.5, 0.85), (8.0, 0.78), (8.5, 0.95), (9.5, 0.40), (10.0, 0.10)
]

// MARK: - ObserveAnimation

@MainActor
final class ObserveAnimation: NSObject, GridAnimation {

    var config = Config()
    var isRunning: Bool { displayLink != nil }

    private weak var grid: CharacterGrid?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?

    // Precomputed
    private var distances: [Float] = []        // from bottom-center origin
    private var centerDistances: [Float] = []  // from grid center
    private var cellSeeds: [UInt32] = []       // per-cell random seeds
    private var cols: Int = 0
    private var rows: Int = 0
    private var maxDistance: Float = 0
    private var maxCenterDistance: Float = 0
    private var colScale: Float = 1.0          // aspect ratio correction for perfect circles

    // Active waves
    private var outboundWaves: [OutboundWave] = []
    private var inboundWaves: [InboundWave] = []
    private var nextOutboundSpawn: Float = 0
    private var nextInboundSpawn: Float = 0
    private var frameSeed: UInt32 = 0

    // MARK: - Public

    func run(on grid: CharacterGrid, completion: @escaping () -> Void) {
        cancel()

        self.grid = grid
        self.completion = completion
        self.cols = GridMetrics.columns
        self.rows = grid.rowCount

        precompute()

        outboundWaves = [OutboundWave(spawnTime: 0)]
        inboundWaves = []
        nextOutboundSpawn = config.outboundPulseInterval
        nextInboundSpawn = 0.5
        frameSeed = 0

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        startTime = 0
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    /// Clears all active waves and resets spawn timers. Call when switching modes.
    func resetWaves() {
        outboundWaves.removeAll()
        inboundWaves.removeAll()
        // Force next spawn to happen on the next frame
        nextOutboundSpawn = 0
        nextInboundSpawn = 0
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        if let grid {
            grid.clearLayer(.transition)
            grid.render()
        }
        grid = nil
    }

    // MARK: - Precompute

    private func precompute() {
        guard let grid else { return }
        let originCol: Float = Float(cols) / 2.0
        let originRow: Float = Float(rows) - 1.0
        let totalCells = rows * cols

        // Compute aspect ratio so waves render as perfect circles on screen
        if let metrics = grid.metrics {
            let gridWidth = grid.bounds.width - 2 * GridMetrics.sideMargin
            let cellWidth = Float(gridWidth / CGFloat(cols))
            let cellHeight = Float(metrics.lineHeight)
            colScale = cellWidth / cellHeight
        }

        distances = [Float](repeating: 0, count: totalCells)
        centerDistances = [Float](repeating: 0, count: totalCells)
        cellSeeds = (0..<totalCells).map { _ in UInt32.random(in: 0...UInt32.max) }
        maxDistance = 0
        maxCenterDistance = 0

        let centerCol: Float = Float(cols) / 2.0
        let centerRow: Float = Float(rows) / 2.0

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col

                // Bottom-center origin (for observe mode)
                let dx = (Float(col) - originCol) * colScale
                let dy = Float(row) - originRow
                let dist = sqrtf(dx * dx + dy * dy)
                distances[idx] = dist
                if dist > maxDistance { maxDistance = dist }

                // Grid center origin (for evaluating mode)
                let cdx = (Float(col) - centerCol) * colScale
                let cdy = Float(row) - centerRow
                let cDist = sqrtf(cdx * cdx + cdy * cdy)
                centerDistances[idx] = cDist
                if cDist > maxCenterDistance { maxCenterDistance = cDist }
            }
        }
    }

    // MARK: - Frame Loop

    @objc private func tick(_ link: CADisplayLink) {
        guard let grid else { cancel(); return }

        if startTime == 0 { startTime = link.timestamp }
        let elapsed = Float(link.timestamp - startTime)

        if !config.isIndefinite && elapsed >= config.duration {
            displayLink?.invalidate()
            displayLink = nil
            grid.clearLayer(.transition)
            grid.render()
            self.grid = nil
            completion?()
            completion = nil
            return
        }

        frameSeed &+= 1

        if config.isEvaluating {
            // --- Evaluating: contracting circles toward grid center ---
            let contractSpeed = maxCenterDistance / 3.0  // 3s edge-to-center

            if elapsed >= nextOutboundSpawn {
                outboundWaves.append(OutboundWave(spawnTime: elapsed))
                nextOutboundSpawn = elapsed + 2.5  // new circle every 2.5s
            }
            outboundWaves.removeAll { wave in
                let wavefront = maxCenterDistance - (elapsed - wave.spawnTime) * contractSpeed
                return wavefront < -config.outboundBandWidth / 2.0
            }
            inboundWaves.removeAll()
        } else {
            // --- Spawn / prune outbound waves ---
            if elapsed >= nextOutboundSpawn {
                outboundWaves.append(OutboundWave(spawnTime: elapsed))
                nextOutboundSpawn = elapsed + config.outboundPulseInterval
            }
            let outboundCycleMax = maxDistance + config.outboundBandWidth / 2.0
            outboundWaves.removeAll { (elapsed - $0.spawnTime) * config.outboundSpeed > outboundCycleMax }

            // --- Sample amplitude ---
            let amplitude = sampleAmplitude(at: elapsed)

            // --- Spawn / prune inbound waves ---
            if config.inboundEnabled {
                let spawnInterval = inboundSpawnInterval(for: amplitude)
                if elapsed >= nextInboundSpawn {
                    inboundWaves.append(InboundWave(spawnTime: elapsed, amplitude: amplitude))
                    nextInboundSpawn = elapsed + spawnInterval
                }
                inboundWaves.removeAll { wave in
                    let wavefront = maxDistance - (elapsed - wave.spawnTime) * config.inboundSpeed
                    return wavefront < -config.inboundBandWidth / 2.0
                }
            }
        }

        // --- Evaluate cells row by row ---
        let halfOutband = config.outboundBandWidth / 2.0
        let halfInband = config.inboundBandWidth / 2.0

        for row in 0..<rows {
            if config.skipRows.contains(row) {
                grid.clearRow(layer: .transition, row: row)
                continue
            }

            var states = [CellState](repeating: .empty, count: cols)
            var rowDirty = false

            for col in 0..<cols {
                let idx = row * cols + col
                let dist = config.isEvaluating ? centerDistances[idx] : distances[idx]
                let seed = cellSeeds[idx]

                var outResult: CellResult?
                var inResult: CellResult?

                // Check outbound waves (or contracting waves in evaluating mode)
                var outWaveId: UInt32 = 0
                for (i, wave) in outboundWaves.enumerated() {
                    let wavefront: Float
                    if config.isEvaluating {
                        let contractSpeed = maxCenterDistance / 3.0
                        wavefront = maxCenterDistance - (elapsed - wave.spawnTime) * contractSpeed
                    } else {
                        wavefront = (elapsed - wave.spawnTime) * config.outboundSpeed
                    }
                    let offset = dist - wavefront
                    if abs(offset) <= halfOutband {
                        outWaveId = UInt32(i) &+ UInt32(bitPattern: Int32(wave.spawnTime * 100))
                        outResult = evaluateOutbound(offset: offset, halfBand: halfOutband, seed: seed, waveId: outWaveId)
                        break
                    }
                }

                // Check inbound waves
                var inWaveId: UInt32 = 0
                for (i, wave) in inboundWaves.enumerated() {
                    let wavefront = maxDistance - (elapsed - wave.spawnTime) * config.inboundSpeed
                    let penetration = wave.amplitude * maxDistance
                    // Wave only reaches cells within penetration depth from edge
                    if dist < (maxDistance - penetration) { continue }
                    let offset = dist - wavefront
                    if abs(offset) <= halfInband {
                        inWaveId = UInt32(i) &+ UInt32(bitPattern: Int32(wave.spawnTime * 100)) &+ 0xFF00
                        inResult = evaluateInbound(offset: offset, halfBand: halfInband, amplitude: wave.amplitude, seed: seed)
                        break
                    }
                }

                // Compose result
                if let outR = outResult, let inR = inResult {
                    // Both waves present - check for core intersection (narrow band)
                    if outR.isCore && inR.isCore {
                        // Interference: flash both to bold color where center lines cross
                        let tier = max(outR.tier, inR.tier)
                        let glyph = pickGlyph(tier: tier, seed: seed, chaos: config.chaos, isInterference: false)
                        states[col] = CellState(character: glyph, color: .bold, bold: true)
                        rowDirty = true
                    } else if outR.isCore || outR.tier >= inR.tier {
                        // Outbound dominates outside core intersection
                        if shouldFill(chance: outR.fillChance, seed: seed, waveId: outWaveId) {
                            let glyph = pickGlyph(tier: outR.tier, seed: seed, chaos: config.chaos, isInterference: false)
                            states[col] = CellState(character: glyph, color: outR.color, bold: false)
                            rowDirty = true
                        }
                    } else {
                        // Inbound dominates
                        if shouldFill(chance: inR.fillChance, seed: seed, waveId: inWaveId) {
                            let glyph = pickGlyph(tier: inR.tier, seed: seed, chaos: config.chaos, isInterference: false)
                            states[col] = CellState(character: glyph, color: .highlight, bold: false)
                            rowDirty = true
                        }
                    }
                } else if let outR = outResult {
                    if shouldFill(chance: outR.fillChance, seed: seed, waveId: outWaveId) {
                        let glyph = pickGlyph(tier: outR.tier, seed: seed, chaos: config.chaos, isInterference: false)
                        states[col] = CellState(character: glyph, color: outR.color, bold: false)
                        rowDirty = true
                    }
                } else if let inR = inResult {
                    if shouldFill(chance: inR.fillChance, seed: seed, waveId: inWaveId) {
                        let glyph = pickGlyph(tier: inR.tier, seed: seed, chaos: config.chaos, isInterference: false)
                        states[col] = CellState(character: glyph, color: .highlight, bold: false)
                        rowDirty = true
                    }
                }
            }

            if rowDirty {
                grid.setRow(layer: .transition, row: row, states: states)
            } else {
                grid.clearRow(layer: .transition, row: row)
            }
        }

        grid.render()
    }

    // MARK: - Cell Evaluation

    private struct CellResult {
        var tier: Int         // 1-5
        var fillChance: Float
        var color: GridColor
        var isCore: Bool = false
    }

    private func evaluateOutbound(offset: Float, halfBand: Float, seed: UInt32, waveId: UInt32) -> CellResult {
        let absOffset = abs(offset)

        // Color: equal mix of bold and tint throughout, with rare red accent
        let isRed = hashFloat(seed, frameSeed) < config.redAccentChance
        let color: GridColor
        if isRed {
            color = .focus
        } else {
            color = hashFloat(seed, waveId &+ 0x4C01) < 0.5 ? .bold : .tint
        }

        if absOffset > 3.5 {
            // Far edge - minimal, sparse
            return CellResult(tier: 1, fillChance: 0.25, color: color, isCore: false)
        } else if absOffset > 2.5 {
            // Near edge - light
            return CellResult(tier: 1, fillChance: 0.45, color: color, isCore: false)
        } else if absOffset > 1.5 {
            // Mid band - moderate
            return CellResult(tier: 2, fillChance: 0.65, color: color, isCore: false)
        } else {
            // Core - medium density (not heavy)
            return CellResult(tier: 3, fillChance: 0.85, color: color, isCore: true)
        }
    }

    private func evaluateInbound(offset: Float, halfBand: Float, amplitude: Float, seed: UInt32) -> CellResult {
        let absOffset = abs(offset)

        // Lighter inbound: tier 1-3 max, similar weight to outbound
        let maxTier: Int
        if amplitude >= 0.6 { maxTier = 3 }
        else if amplitude >= 0.3 { maxTier = 2 }
        else { maxTier = 1 }

        if absOffset > 1.5 {
            // Far edge - minimal
            return CellResult(tier: 1, fillChance: 0.20 * amplitude, color: .highlight, isCore: false)
        } else if absOffset > 0.5 {
            // Near edge
            let tier = min(maxTier, 2)
            return CellResult(tier: tier, fillChance: 0.40 * amplitude, color: .highlight, isCore: false)
        } else {
            // Core
            return CellResult(tier: maxTier, fillChance: 0.70 * amplitude, color: .highlight, isCore: true)
        }
    }

    // MARK: - Glyph Selection with Chaos

    private func pickGlyph(tier: Int, seed: UInt32, chaos: Float, isInterference: Bool) -> Character {
        let pool = isInterference ? interferenceGlyphs : allTiers[max(0, min(4, tier - 1))]

        // Quantized epoch: lower chaos = glyphs change less often
        let changeRate = max(1, Int((1.0 - chaos) * 20.0) + 1)
        let epoch = UInt32(frameSeed / UInt32(changeRate))

        let h = hash(seed, epoch)
        let index = Int(h) % pool.count
        return pool[index]
    }

    private func shouldFill(chance: Float, seed: UInt32, waveId: UInt32) -> Bool {
        // Use waveId instead of frameSeed so fill pattern is stable per wave
        return hashFloat(seed, waveId) < chance
    }

    // MARK: - Amplitude Sampling

    private func sampleAmplitude(at t: Float) -> Float {
        let keyframes = amplitudeKeyframes
        let effectiveTime = config.isIndefinite ? t.truncatingRemainder(dividingBy: config.duration) : t

        // Find surrounding keyframes
        if effectiveTime <= keyframes[0].time { return keyframes[0].value }
        if effectiveTime >= keyframes[keyframes.count - 1].time { return keyframes[keyframes.count - 1].value }

        for i in 0..<keyframes.count - 1 {
            if effectiveTime >= keyframes[i].time && effectiveTime < keyframes[i + 1].time {
                let t0 = keyframes[i].time
                let t1 = keyframes[i + 1].time
                let v0 = keyframes[i].value
                let v1 = keyframes[i + 1].value
                let frac = (t - t0) / (t1 - t0)
                // Smooth interpolation
                let smooth = frac * frac * (3.0 - 2.0 * frac)
                let base = v0 + (v1 - v0) * smooth
                // Apply jitter
                let jitter = (hashFloat(frameSeed, 0xDEAD) - 0.5) * 0.10
                return max(0, min(1, base + jitter))
            }
        }

        return keyframes[keyframes.count - 1].value
    }

    private func inboundSpawnInterval(for amplitude: Float) -> Float {
        if amplitude >= 0.8 { return 0.3 }
        if amplitude >= 0.6 { return 0.6 }
        if amplitude >= 0.3 { return 1.0 }
        return 2.0
    }

    // MARK: - Fast Hashing

    /// Simple deterministic hash returning UInt32
    private func hash(_ a: UInt32, _ b: UInt32) -> UInt32 {
        var h = a &+ 0x9e3779b9
        h = h ^ (b &* 0x85ebca6b)
        h = h &* 0xcc9e2d51
        h = (h ^ (h >> 16)) &* 0x85ebca6b
        h = h ^ (h >> 13)
        return h
    }

    /// Hash returning Float in [0, 1)
    private func hashFloat(_ a: UInt32, _ b: UInt32) -> Float {
        return Float(hash(a, b) & 0x00FFFFFF) / Float(0x01000000)
    }
}

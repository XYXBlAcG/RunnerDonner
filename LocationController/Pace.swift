import Foundation

struct Pace {
    static func seconds(_ text: String) -> Double? {
        let p = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "：", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, let m = Int(p[0]), let s = Int(p[1]), (0...60).contains(m), (0...59).contains(s) else { return nil }
        let total = m * 60 + s
        return (60...3600).contains(total) ? Double(total) : nil
    }
    static func label(_ seconds: Double) -> String {
        let n = Int(seconds.rounded())
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}
// A new bounded target is sampled every 20 seconds; smoothstep joins targets
// with zero slope at each join. Targets vary pace (seconds/km), not coordinates.
struct PaceProfile {
    let base: Double
    let amplitude: Double
    let targets: [Double]
    init(base: Double, amplitude: Double, duration: Double, random: () -> Double = { Double.random(in: -1...1) }) {
        self.base = base
        let bounded = max(0, min(amplitude, base - 60, 3600 - base))
        self.amplitude = bounded
        let count = max(2, Int(ceil(duration / 20)) + 2)
        targets = [base] + (1..<count).map { _ in base + bounded * max(-1, min(1, random())) }
    }
    func seconds(at elapsed: Double) -> Double {
        let pos = max(0, elapsed) / 20
        let i = min(Int(pos), targets.count - 2)
        let t = min(1, max(0, pos - Double(i)))
        let smooth = t * t * (3 - 2 * t)
        return targets[i] + (targets[i + 1] - targets[i]) * smooth
    }
}

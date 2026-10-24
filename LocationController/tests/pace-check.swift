import Foundation
@main struct Checks {
    static func main() {
        precondition(Pace.seconds("6:00") == 360)
        precondition(Pace.seconds(" 7：30 ") == 450)
        for value in ["0:59", "61:00", "6:60", "6", "-1:30", "9999999999999999999999999:00", "NaN:00"] { precondition(Pace.seconds(value) == nil) }
        var index = 0
        let samples = [1.0, -1.0, 0.5, -0.5]
        let p = PaceProfile(base: 360, amplitude: 15, duration: 200, random: { defer { index += 1 }; return samples[index % samples.count] })
        precondition(p.seconds(at: 0) == 360)
        var last = p.seconds(at: 0)
        for i in 1...20000 {
            let time = Double(i) / 100
            let pace = p.seconds(at: time)
            precondition(pace.isFinite && (345...375).contains(pace))
            precondition(abs(pace - last) < 0.03)
            last = pace
        }
        precondition(p.seconds(at: 20) == 375 && p.seconds(at: 40) == 345)
        let fixed = PaceProfile(base: 360, amplitude: 0, duration: 200)
        precondition(fixed.targets.allSatisfy { $0 == 360 })
        let nearMinimum = PaceProfile(base: 62, amplitude: 30, duration: 50, random: { -1 })
        precondition(nearMinimum.targets.allSatisfy { $0 >= 60 })
        let nearMaximum = PaceProfile(base: 3598, amplitude: 30, duration: 50, random: { 1 })
        precondition(nearMaximum.targets.allSatisfy { $0 <= 3600 })
        print("PASS: pace parsing, extreme input, bounded variation, smooth joins, fixed mode, and limit clamping")
    }
}

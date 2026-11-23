import AppKit
import SwiftUI

enum CatMood: String {
    case idle, typing, excited, sleeping
}

/// 猫的状态机：只接收"按了一下"这个事件，不关心是哪个键。
final class CatModel: ObservableObject {
    @Published var leftPawDown = false
    @Published var rightPawDown = false
    @Published var mood: CatMood = .idle
    @Published var theme: CatTheme
    @Published var todayCount: Int
    /// 没有键盘权限时，猫头顶显示提示气泡
    @Published var needsPermission = false

    /// 打字速度（键/秒），按最近 2 秒统计
    private var recent: [TimeInterval] = []
    private var lastKey: TimeInterval = 0
    private var nextIsLeft = true
    private var pawUpWork: [Bool: DispatchWorkItem] = [:]
    private var tick: Timer?

    static let sleepAfter: TimeInterval = 30
    static let excitedRate: Double = 6

    private let defaults = UserDefaults.standard

    init() {
        theme = CatModel.loadTheme()
        let today = CatModel.dayKey()
        todayCount = defaults.string(forKey: "countDay") == today ? defaults.integer(forKey: "countValue") : 0
        lastKey = Date().timeIntervalSince1970
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateMood() }
    }

    // MARK: 按键

    func keyPressed() {
        let now = Date().timeIntervalSince1970
        lastKey = now
        recent.append(now)
        recent.removeAll { now - $0 > 2 }

        let left = nextIsLeft
        nextIsLeft.toggle()
        setPaw(left: left, down: true)
        pawUpWork[left]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.setPaw(left: left, down: false) }
        pawUpWork[left] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)

        bumpCount()
        updateMood()
    }

    private func setPaw(left: Bool, down: Bool) {
        if left { leftPawDown = down } else { rightPawDown = down }
    }

    private func updateMood() {
        let now = Date().timeIntervalSince1970
        recent.removeAll { now - $0 > 2 }
        let idleFor = now - lastKey
        let rate = Double(recent.count) / 2
        let newMood: CatMood
        if idleFor > CatModel.sleepAfter { newMood = .sleeping }
        else if idleFor > 0.8 { newMood = .idle }
        else if rate >= CatModel.excitedRate { newMood = .excited }
        else { newMood = .typing }
        if newMood != mood { mood = newMood }
    }

    // MARK: 今日计数

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func bumpCount() {
        let today = CatModel.dayKey()
        if defaults.string(forKey: "countDay") != today {
            defaults.set(today, forKey: "countDay")
            todayCount = 0
        }
        todayCount += 1
        defaults.set(todayCount, forKey: "countValue")
    }

    // MARK: 毛色

    func setTheme(_ t: CatTheme) {
        theme = t
        defaults.set(t.id, forKey: "themeId")
    }

    func setCustomFur(_ color: NSColor) {
        defaults.set(Int(color.hexValue), forKey: "customFur")
        setTheme(.custom(fur: color))
    }

    private static func loadTheme() -> CatTheme {
        let d = UserDefaults.standard
        let id = d.string(forKey: "themeId") ?? "blue"
        if id == "custom", d.object(forKey: "customFur") != nil {
            return .custom(fur: NSColor(hex: UInt32(d.integer(forKey: "customFur"))))
        }
        return CatTheme.presets.first { $0.id == id } ?? CatTheme.presets[0]
    }

    /// 仅用于截图预览
    func force(mood: CatMood, left: Bool, right: Bool) {
        tick?.invalidate()
        self.mood = mood
        leftPawDown = left
        rightPawDown = right
    }
}

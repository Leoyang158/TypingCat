import AppKit
import SwiftUI

enum CatMood: String {
    case idle, typing, excited, sleeping
}

/// 从键上弹起来的字母
struct FloatingLetter: Identifiable {
    let id = UUID()
    let text: String
    let key: KeyPos
    let born: TimeInterval
}

/// 猫的状态机。统一使用 `CatModel.now`（timeIntervalSinceReferenceDate）计时，与绘制用的时钟一致。
final class CatModel: ObservableObject {
    // 爪子正按着的键（nil 表示抬起）
    @Published var leftKey: KeyPos?
    @Published var rightKey: KeyPos?
    @Published var mood: CatMood = .idle
    @Published var theme: CatTheme
    @Published var todayCount: Int
    /// 没有键盘权限时，猫头顶显示提示气泡
    @Published var needsPermission = false

    // 显示字母
    @Published var letters: [FloatingLetter] = []
    @Published var typedLine = ""
    var lastTypedAt: TimeInterval = -100
    @Published var showLetters: Bool {
        didSet { defaults.set(showLetters, forKey: "showLetters"); if !showLetters { letters = []; typedLine = "" } }
    }

    // 鼠标与 rua
    /// 鼠标在设计坐标系中的位置；绘制每帧读取，不触发刷新
    var mouse: CGPoint?
    @Published var isPetted = false
    var happyUntil: TimeInterval = 0
    var onPetStart: (() -> Void)?
    var onPetEnd: (() -> Void)?
    private var rubEnergy = 0.0
    private var lastMouse: CGPoint?

    private var recent: [TimeInterval] = []
    private var lastKey: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    private var nextIsLeft = true
    private var pawUpWork: [Bool: DispatchWorkItem] = [:]
    private var tick: Timer?

    static let sleepAfter: TimeInterval = 30
    static let excitedRate: Double = 6
    static var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    private let defaults = UserDefaults.standard

    init() {
        theme = CatModel.loadTheme()
        showLetters = UserDefaults.standard.object(forKey: "showLetters") as? Bool ?? true
        let today = CatModel.dayKey()
        todayCount = defaults.string(forKey: "countDay") == today ? defaults.integer(forKey: "countValue") : 0
        lastKey = CatModel.now - 10
        lastActivity = CatModel.now
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateMood() }
    }

    // MARK: 按键

    func keyPressed(_ info: KeyInfo) {
        let now = CatModel.now
        lastKey = now
        lastActivity = now
        recent.append(now)
        recent.removeAll { now - $0 > 2 }

        // 按键在左半边用左爪，右半边用右爪；空格和未知键左右交替
        let pos = KeyLayout.map[info.keyCode]
        let left: Bool
        if let pos, pos.row < 3 { left = pos.col < 5 } else { left = nextIsLeft }
        nextIsLeft = !left
        let key = pos ?? KeyPos(row: 1, col: left ? Int.random(in: 0...4) : Int.random(in: 5...9))

        setPaw(left: left, key: key)
        pawUpWork[left]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.setPaw(left: left, key: nil) }
        pawUpWork[left] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)

        if showLetters, let label = KeyLayout.label(for: info) {
            letters.removeAll { now - $0.born > 0.8 }
            letters.append(FloatingLetter(text: label, key: key, born: now))
            if letters.count > 10 { letters.removeFirst() }
            updateLine(info)
        }

        bumpCount()
        updateMood()
    }

    /// 头顶气泡里的一行字：像真的在打字一样，支持退格和回车
    private func updateLine(_ info: KeyInfo) {
        switch info.keyCode {
        case 51, 117: if !typedLine.isEmpty { typedLine.removeLast() }
        case 36, 76: typedLine = ""
        case 49, 48: typedLine += " "
        case 53, 123, 124, 125, 126: break
        default:
            guard !info.command else { break }
            typedLine += info.chars.trimmingCharacters(in: .controlCharacters)
        }
        if typedLine.count > 18 { typedLine = String(typedLine.suffix(18)) }
        lastTypedAt = CatModel.now
    }

    private func setPaw(left: Bool, key: KeyPos?) {
        if left { leftKey = key } else { rightKey = key }
    }

    private func updateMood() {
        let now = CatModel.now
        recent.removeAll { now - $0 > 2 }
        let idleFor = now - lastKey
        let rate = Double(recent.count) / 2
        let newMood: CatMood
        if now - lastActivity > CatModel.sleepAfter { newMood = .sleeping }
        else if idleFor > 0.8 { newMood = .idle }
        else if rate >= CatModel.excitedRate { newMood = .excited }
        else { newMood = .typing }
        if newMood != mood { mood = newMood }
    }

    // MARK: 鼠标 / rua

    static func inHead(_ p: CGPoint) -> Bool {
        let dx = (p.x - 110) / 66, dy = (p.y - 75) / 54
        return dx * dx + dy * dy <= 1
    }

    /// 约 30Hz 调用一次；p 为鼠标在设计坐标系中的位置
    func trackMouse(_ p: CGPoint?) {
        mouse = p
        var moved = 0.0
        if let p, let lp = lastMouse, CatModel.inHead(p) {
            moved = min(hypot(p.x - lp.x, p.y - lp.y), 30)
        }
        lastMouse = p
        // 在头上来回蹭会不断积累"能量"，停下后很快衰减
        rubEnergy = rubEnergy * 0.9 + moved
        if !isPetted && rubEnergy > 45 {
            isPetted = true
            onPetStart?()
        } else if isPetted && rubEnergy < 6 {
            isPetted = false
            onPetEnd?()
        }
        if isPetted {
            lastActivity = CatModel.now
            if mood == .sleeping { updateMood() }
        }
    }

    /// 被点了一下
    func poke() {
        happyUntil = CatModel.now + 1.2
        lastActivity = CatModel.now
        updateMood()
        objectWillChange.send()
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
    func force(mood: CatMood, left: KeyPos?, right: KeyPos?) {
        tick?.invalidate()
        self.mood = mood
        leftKey = left
        rightKey = right
    }
}

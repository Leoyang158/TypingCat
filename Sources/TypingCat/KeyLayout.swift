import CoreGraphics
import Foundation

/// 猫面前小键盘上的一个键位
struct KeyPos: Hashable {
    var row: Int   // 0...2 为字母行，3 为空格
    var col: Int
}

/// 小键盘的几何布局（设计坐标系 220 x 180），绘制和爪子定位共用
enum KeyLayout {
    static let keyW = 12.0, keyH = 7.5, gap = 3.0, top = 129.0, rowStep = 10.0
    static let rowCounts = [10, 10, 9]
    static let space = CGRect(x: 80, y: top + 3 * rowStep, width: 60, height: keyH - 1)

    static func rect(_ k: KeyPos) -> CGRect {
        if k.row == 3 { return space }
        let n = rowCounts[k.row]
        let total = Double(n) * keyW + Double(n - 1) * gap
        let x0 = 110 - total / 2 + (k.row == 1 ? 3 : 0)
        return CGRect(x: x0 + Double(k.col) * (keyW + gap), y: top + Double(k.row) * rowStep,
                      width: keyW, height: keyH)
    }

    /// macOS 键码（ANSI 布局）→ 小键盘位置
    static let map: [Int: KeyPos] = {
        var m: [Int: KeyPos] = [:]
        let rows: [[Int]] = [
            [12, 13, 14, 15, 17, 16, 32, 34, 31, 35],   // Q W E R T Y U I O P
            [0, 1, 2, 3, 5, 4, 38, 40, 37, 41],          // A S D F G H J K L ;
            [6, 7, 8, 9, 11, 45, 46, 43, 47],            // Z X C V B N M , .
        ]
        for (r, codes) in rows.enumerated() {
            for (c, code) in codes.enumerated() { m[code] = KeyPos(row: r, col: c) }
        }
        // 数字行映射到第一行
        for (c, code) in [18, 19, 20, 21, 23, 22, 26, 28, 25, 29].enumerated() { m[code] = KeyPos(row: 0, col: c) }
        m[49] = KeyPos(row: 3, col: 0)                      // 空格
        m[36] = KeyPos(row: 1, col: 9); m[76] = KeyPos(row: 1, col: 9)  // 回车
        m[51] = KeyPos(row: 0, col: 9); m[117] = KeyPos(row: 0, col: 9) // 删除
        m[48] = KeyPos(row: 0, col: 0)                      // Tab
        m[53] = KeyPos(row: 0, col: 0)                      // Esc
        m[44] = KeyPos(row: 2, col: 8); m[39] = KeyPos(row: 1, col: 9)  // / '
        m[123] = KeyPos(row: 2, col: 6); m[124] = KeyPos(row: 2, col: 8)
        m[125] = KeyPos(row: 2, col: 7); m[126] = KeyPos(row: 1, col: 7)
        return m
    }()

    /// 浮在键上的字母
    static func label(for info: KeyInfo) -> String? {
        let special: [Int: String] = [36: "⏎", 76: "⏎", 51: "⌫", 117: "⌦", 48: "⇥", 53: "esc",
                                      49: "␣", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let s = special[info.keyCode] { return s }
        let ch = info.chars.trimmingCharacters(in: .controlCharacters)
        guard !ch.isEmpty else { return nil }
        return info.command ? "⌘" + ch.uppercased() : ch
    }
}

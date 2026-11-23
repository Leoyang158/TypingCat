import AppKit
import SwiftUI

/// 一套毛色配色（英短常见色系 + 自定义）
struct CatTheme: Equatable {
    var id: String
    var name: String
    var fur: Color
    var shade: Color      // 阴影/身体暗部
    var light: Color      // 嘴套、爪子高光
    var innerEar: Color
    var eye: Color
    var nose: Color

    static let presets: [CatTheme] = [
        .make(id: "blue",   name: "蓝猫（经典）", fur: 0x8F9BAA, eye: 0xE9A23B, nose: 0x5E6877),
        .make(id: "silver", name: "银渐层",       fur: 0xDADFE5, eye: 0x47A878, nose: 0xE39AA0),
        .make(id: "golden", name: "金渐层",       fur: 0xE6C07C, eye: 0x3E9E6A, nose: 0xD98C7A),
        .make(id: "cream",  name: "奶油",         fur: 0xF0D7B4, eye: 0xD9893A, nose: 0xE7A39A),
        .make(id: "lilac",  name: "丁香",         fur: 0xC9B8BC, eye: 0xE3A04A, nose: 0xB98A92),
        .make(id: "white",  name: "白猫",         fur: 0xF6F4EF, eye: 0x4A8FD8, nose: 0xF0A6AE),
        .make(id: "black",  name: "黑猫",         fur: 0x3B3B42, eye: 0xF2C14E, nose: 0x26262B),
    ]

    static func make(id: String, name: String, fur: UInt32, eye: UInt32, nose: UInt32) -> CatTheme {
        custom(id: id, name: name, fur: NSColor(hex: fur), eye: NSColor(hex: eye), nose: NSColor(hex: nose))
    }

    /// 由主毛色自动推导暗部/亮部
    static func custom(id: String = "custom", name: String = "自定义", fur: NSColor,
                       eye: NSColor = NSColor(hex: 0xE9A23B), nose: NSColor? = nil) -> CatTheme {
        let f = fur.usingColorSpace(.sRGB) ?? fur
        let isDark = f.brightnessComponent < 0.35
        let shade = f.blended(withFraction: isDark ? 0.25 : 0.14, of: .black) ?? f
        let light = f.blended(withFraction: isDark ? 0.18 : 0.45, of: .white) ?? f
        let ear = f.blended(withFraction: 0.45, of: NSColor(hex: 0xF2A7B0)) ?? f
        let n = nose ?? (f.blended(withFraction: 0.5, of: NSColor(hex: 0xE08A95)) ?? f)
        return CatTheme(id: id, name: name, fur: Color(nsColor: f), shade: Color(nsColor: shade),
                        light: Color(nsColor: light), innerEar: Color(nsColor: ear),
                        eye: Color(nsColor: eye), nose: Color(nsColor: n))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    var hexValue: UInt32 {
        let c = usingColorSpace(.sRGB) ?? self
        return (UInt32(c.redComponent * 255) << 16) | (UInt32(c.greenComponent * 255) << 8) | UInt32(c.blueComponent * 255)
    }
}

import SwiftUI

/// 设计坐标系 220 x 180，绘制时按窗口大小等比缩放。
struct CatView: View {
    @ObservedObject var model: CatModel
    /// 截图模式下固定时间，避免眨眼等随机效果
    var fixedTime: Double? = nil

    static let designSize = CGSize(width: 220, height: 180)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil)) { tl in
            let t = fixedTime ?? tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / Self.designSize.width, y: size.height / Self.designSize.height)
                CatPainter(model: model, t: t).draw(&ctx)
            }
        }
    }
}

private struct CatPainter {
    let model: CatModel
    let t: Double

    var th: CatTheme { model.theme }
    var mood: CatMood { model.mood }
    var sleeping: Bool { mood == .sleeping }
    /// 被 rua 或被点了一下
    var happy: Bool { model.isPetted || t < model.happyUntil }

    func draw(_ ctx: inout GraphicsContext) {
        // 睡觉时头低一点，并随呼吸起伏
        let breathe = sleeping ? sin(t * 1.6) * 1.2 : 0
        let headDY = (sleeping ? 6 : 0) + breathe

        shadow(&ctx)
        tail(&ctx)
        bodyShape(&ctx, breathe: breathe)
        head(&ctx, dy: headDY)
        keyboard(&ctx)
        miniMouse(&ctx)
        paw(&ctx, left: true, key: model.leftKey)
        paw(&ctx, left: false, key: model.rightKey)
        effects(&ctx)
        poppedLetters(&ctx)
        if model.needsPermission { permissionBubble(&ctx) } else { typedBubble(&ctx) }
    }

    // MARK: - 气泡

    static let ink = Color(red: 0.25, green: 0.27, blue: 0.32)

    /// 头顶的白色对话气泡，返回内容区域
    func bubble(_ ctx: inout GraphicsContext, width: Double) -> CGRect {
        let w = min(max(width, 40), 210)
        let r = CGRect(x: 110 - w / 2, y: 0, width: w, height: 20)
        var p = Path(roundedRect: r, cornerRadius: 10)
        p.move(to: CGPoint(x: 104, y: r.maxY))
        p.addLine(to: CGPoint(x: 110, y: r.maxY + 6))
        p.addLine(to: CGPoint(x: 116, y: r.maxY))
        ctx.fill(p, with: .color(.white))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(.black.opacity(0.12)), lineWidth: 1)
        return r
    }

    func permissionBubble(_ ctx: inout GraphicsContext) {
        let r = bubble(&ctx, width: 140)
        let text = Text("点我开启键盘权限 🐾")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Self.ink)
        ctx.draw(text, at: CGPoint(x: r.midX, y: r.midY))
    }

    /// 猫"打出来"的一行字，停止打字 2.5 秒后淡出
    func typedBubble(_ ctx: inout GraphicsContext) {
        guard model.showLetters, !model.typedLine.isEmpty else { return }
        let age = t - model.lastTypedAt
        guard age >= 0, age < 3 else { return }
        var c = ctx
        c.opacity = age < 2.5 ? 1 : (3 - age) / 0.5
        let cursor = Int(t * 2.5) % 2 == 0 ? "_" : " "
        let text = c.resolve(Text(model.typedLine + cursor)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Self.ink))
        let size = text.measure(in: CGSize(width: 400, height: 30))
        let r = bubble(&c, width: size.width + 18)
        c.draw(text, at: CGPoint(x: r.midX, y: r.midY))
    }

    /// 从键上弹起来的字母
    func poppedLetters(_ ctx: inout GraphicsContext) {
        for l in model.letters {
            let age = t - l.born
            guard age >= 0, age < 0.8 else { continue }
            let p = age / 0.8
            let k = KeyLayout.rect(l.key)
            let rise = 1 - pow(1 - p, 3)
            let center = CGPoint(x: min(max(k.midX, 14), 206), y: k.minY - 8 - rise * 24)
            var c = ctx
            c.opacity = 1 - p * p
            let text = c.resolve(Text(l.text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Self.ink))
            let size = text.measure(in: CGSize(width: 100, height: 30))
            let w = max(17, size.width + 9)
            let r = CGRect(x: center.x - w / 2, y: center.y - 8.5, width: w, height: 17)
            c.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(.white))
            c.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(.black.opacity(0.15)), lineWidth: 1)
            c.draw(text, at: center)
        }
    }

    // MARK: - 部件

    func shadow(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(ellipseIn: CGRect(x: 30, y: 162, width: 160, height: 12)),
                 with: .color(.black.opacity(0.18)))
    }

    func tail(_ ctx: inout GraphicsContext) {
        let speed: Double = switch mood {
        case .excited: 9
        case .typing: 5
        case .idle: 2
        case .sleeping: 0.6
        }
        let amp: Double = sleeping ? 3 : 10
        let sway = sin(t * speed) * amp
        var p = Path()
        p.move(to: CGPoint(x: 168, y: 130))
        p.addQuadCurve(to: CGPoint(x: 198 + sway, y: sleeping ? 118 : 74),
                       control: CGPoint(x: 214, y: 128))
        ctx.stroke(p, with: .color(th.shade), style: StrokeStyle(lineWidth: 17, lineCap: .round))
        ctx.stroke(p, with: .color(th.fur), style: StrokeStyle(lineWidth: 13, lineCap: .round))
    }

    func bodyShape(_ ctx: inout GraphicsContext, breathe: Double) {
        let r = CGRect(x: 30, y: 82 - breathe, width: 160, height: 78 + breathe)
        ctx.fill(Path(ellipseIn: r), with: .color(th.shade))
        ctx.fill(Path(ellipseIn: r.insetBy(dx: 6, dy: 4).offsetBy(dx: 0, dy: -3)), with: .color(th.fur))
    }

    func head(_ ctx: inout GraphicsContext, dy: Double) {
        var c = ctx
        c.translateBy(x: 0, y: dy)
        if model.isPetted || mood == .idle {
            // 被 rua 时脑袋左右蹭；发呆时慢慢歪头
            let a = model.isPetted ? sin(t * 5) * 0.05 : sin(t * 0.8) * 0.06
            c.translateBy(x: 110, y: 120)
            c.rotate(by: .radians(a))
            c.translateBy(x: -110, y: -120)
        }

        // 耳朵：英短的耳朵小、圆、分得很开
        ear(&c, tip: CGPoint(x: 55, y: 22), a: CGPoint(x: 52, y: 56), b: CGPoint(x: 85, y: 31))
        ear(&c, tip: CGPoint(x: 165, y: 22), a: CGPoint(x: 168, y: 56), b: CGPoint(x: 135, y: 31))

        // 大圆脸 + 腮帮子
        c.fill(Path(ellipseIn: CGRect(x: 44, y: 22, width: 132, height: 106)), with: .color(th.fur))
        c.fill(Path(ellipseIn: CGRect(x: 50, y: 74, width: 56, height: 46)), with: .color(th.fur))
        c.fill(Path(ellipseIn: CGRect(x: 114, y: 74, width: 56, height: 46)), with: .color(th.fur))

        // 额头的一点暗纹
        for dx in [-8.0, 0, 8] {
            var s = Path()
            s.move(to: CGPoint(x: 110 + dx, y: 32))
            s.addLine(to: CGPoint(x: 110 + dx * 0.7, y: 42))
            c.stroke(s, with: .color(th.shade.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }

        eyes(&c)

        // 嘴套
        c.fill(Path(ellipseIn: CGRect(x: 89, y: 85, width: 23, height: 17)), with: .color(th.light))
        c.fill(Path(ellipseIn: CGRect(x: 108, y: 85, width: 23, height: 17)), with: .color(th.light))

        // 鼻子
        var nose = Path()
        nose.move(to: CGPoint(x: 104, y: 82))
        nose.addLine(to: CGPoint(x: 116, y: 82))
        nose.addQuadCurve(to: CGPoint(x: 110, y: 89), control: CGPoint(x: 115, y: 87))
        nose.addQuadCurve(to: CGPoint(x: 104, y: 82), control: CGPoint(x: 105, y: 87))
        c.fill(nose, with: .color(th.nose))

        // 小舌头：平时露一点舌尖，专心打字时歪着伸出来
        if !sleeping {
            let typing = mood == .typing || mood == .excited
            let tw = typing ? 7.5 : 6.0, tl = typing ? 8.0 : 4.5
            let tx = typing ? 113.5 : 110.0
            let tongue = CGRect(x: tx - tw / 2, y: 92.5, width: tw, height: tl)
            c.fill(Path(roundedRect: tongue, cornerRadius: tw / 2), with: .color(Color(red: 1, green: 0.55, blue: 0.62)))
            var mid = Path()
            mid.move(to: CGPoint(x: tx, y: 94)); mid.addLine(to: CGPoint(x: tx, y: 92.5 + tl - 2.5))
            c.stroke(mid, with: .color(Color(red: 0.85, green: 0.35, blue: 0.45).opacity(0.6)), lineWidth: 1)
        }

        // 嘴巴 "ω"
        let ink = Color.black.opacity(0.45)
        var m = Path()
        m.move(to: CGPoint(x: 110, y: 89))
        m.addLine(to: CGPoint(x: 110, y: 92))
        m.move(to: CGPoint(x: 103, y: 92))
        m.addQuadCurve(to: CGPoint(x: 110, y: 92), control: CGPoint(x: 106.5, y: 97))
        m.addQuadCurve(to: CGPoint(x: 117, y: 92), control: CGPoint(x: 113.5, y: 97))
        c.stroke(m, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

        // 胡须
        var w = Path()
        for (y0, y1) in [(91.0, 86.0), (96.0, 97.0)] {
            w.move(to: CGPoint(x: 88, y: y0)); w.addLine(to: CGPoint(x: 64, y: y1))
            w.move(to: CGPoint(x: 132, y: y0)); w.addLine(to: CGPoint(x: 156, y: y1))
        }
        c.stroke(w, with: .color(th.light.opacity(0.9)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

        // 腮红：平时淡淡的，兴奋或开心时更红
        let blush = mood == .excited || happy ? 0.5 : 0.22
        for x in [64.0, 140.0] {
            c.fill(Path(ellipseIn: CGRect(x: x, y: 86, width: 16, height: 9)),
                   with: .color(Color(red: 1, green: 0.45, blue: 0.5).opacity(blush)))
        }

        // 打字太快：头上冒汗珠
        if mood == .excited {
            let drop = CGPoint(x: 160, y: 40 + (t * 1.5).truncatingRemainder(dividingBy: 1) * 6)
            var d = Path()
            d.move(to: CGPoint(x: drop.x, y: drop.y - 8))
            d.addQuadCurve(to: CGPoint(x: drop.x, y: drop.y + 4), control: CGPoint(x: drop.x + 8, y: drop.y + 2))
            d.addQuadCurve(to: CGPoint(x: drop.x, y: drop.y - 8), control: CGPoint(x: drop.x - 8, y: drop.y + 2))
            c.fill(d, with: .color(Color(red: 0.55, green: 0.78, blue: 0.98)))
            c.fill(Path(ellipseIn: CGRect(x: drop.x - 2.5, y: drop.y - 2, width: 2.2, height: 3)), with: .color(.white.opacity(0.8)))
        }

        // 睡觉：鼻涕泡一大一小
        if sleeping {
            let r = 3 + 3.5 * abs(sin(t * 0.9))
            let b = CGRect(x: 117, y: 84 - r, width: r * 2, height: r * 2)
            c.fill(Path(ellipseIn: b), with: .color(Color(red: 0.75, green: 0.88, blue: 1).opacity(0.55)))
            c.stroke(Path(ellipseIn: b), with: .color(.white.opacity(0.9)), lineWidth: 1)
            c.fill(Path(ellipseIn: CGRect(x: b.minX + r * 0.5, y: b.minY + r * 0.4, width: r * 0.5, height: r * 0.5)),
                   with: .color(.white.opacity(0.9)))
        }
    }

    func ear(_ ctx: inout GraphicsContext, tip: CGPoint, a: CGPoint, b: CGPoint) {
        var p = Path()
        p.move(to: a); p.addLine(to: tip); p.addLine(to: b); p.closeSubpath()
        ctx.fill(p, with: .color(th.fur))
        ctx.stroke(p, with: .color(th.fur), style: StrokeStyle(lineWidth: 11, lineJoin: .round))
        // 内耳
        let cx = (a.x + b.x + tip.x) / 3, cy = (a.y + b.y + tip.y) / 3 + 3
        func shrink(_ q: CGPoint) -> CGPoint { CGPoint(x: cx + (q.x - cx) * 0.55, y: cy + (q.y - cy) * 0.55) }
        var inner = Path()
        inner.move(to: shrink(a)); inner.addLine(to: shrink(tip)); inner.addLine(to: shrink(b)); inner.closeSubpath()
        ctx.fill(inner, with: .color(th.innerEar))
        ctx.stroke(inner, with: .color(th.innerEar), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
    }

    /// 发呆时每 9 秒对一次眼（持续约 1.6 秒）
    var derp: Bool { mood == .idle && !happy && t.truncatingRemainder(dividingBy: 9) > 7.4 }

    func eyes(_ ctx: inout GraphicsContext) {
        // 眼距略宽，豆豆眼更显呆
        let centers = [CGPoint(x: 84, y: 69), CGPoint(x: 136, y: 69)]
        let ink = Color.black.opacity(0.75)
        let line = StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)

        // 每 ~4.3 秒眨一次眼
        let blinking = mood != .sleeping && t.truncatingRemainder(dividingBy: 4.3) < 0.14

        for (i, c) in centers.enumerated() {
            let isLeft = i == 0
            if happy {
                // 开心的 ^ ^ 眼
                var p = Path()
                p.move(to: CGPoint(x: c.x - 10, y: c.y + 4))
                p.addQuadCurve(to: CGPoint(x: c.x + 10, y: c.y + 4), control: CGPoint(x: c.x, y: c.y - 10))
                ctx.stroke(p, with: .color(ink), style: line)
            } else if sleeping {
                var p = Path()
                p.move(to: CGPoint(x: c.x - 10, y: c.y))
                p.addQuadCurve(to: CGPoint(x: c.x + 10, y: c.y), control: CGPoint(x: c.x, y: c.y + 8))
                ctx.stroke(p, with: .color(ink), style: line)
            } else if mood == .excited {
                // 手忙脚乱的 > <
                let d: Double = isLeft ? 1 : -1
                var p = Path()
                p.move(to: CGPoint(x: c.x - 7 * d, y: c.y - 7))
                p.addLine(to: CGPoint(x: c.x + 6 * d, y: c.y))
                p.addLine(to: CGPoint(x: c.x - 7 * d, y: c.y + 7))
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            } else if blinking {
                var p = Path()
                p.move(to: CGPoint(x: c.x - 10, y: c.y + 1))
                p.addLine(to: CGPoint(x: c.x + 10, y: c.y + 1))
                ctx.stroke(p, with: .color(ink), style: line)
            } else {
                // 大圆豆豆眼：瞳孔又大又圆，两颗高光
                let r = 13.0
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(th.eye))
                var look = lookOffset(from: c)
                if derp {
                    // 对眼：两只瞳孔都往鼻子靠
                    look = CGVector(dx: isLeft ? 4.5 : -4.5, dy: 1.5)
                }
                let pr = 8.5
                let pc = CGPoint(x: c.x + look.dx, y: c.y + look.dy)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                         with: .color(Color(white: 0.08)))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x + 0.5, y: pc.y - 6.5, width: 6, height: 6)),
                         with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - 5, y: pc.y + 2, width: 2.8, height: 2.8)),
                         with: .color(.white.opacity(0.9)))
            }
        }
    }

    /// 瞳孔偏移：最多 4.5（设计单位），朝向鼠标；打字时盯着键盘
    func lookOffset(from eye: CGPoint) -> CGVector {
        if mood == .typing || mood == .excited { return CGVector(dx: 0, dy: 3.5) }
        guard let m = model.mouse else { return .zero }
        let dx = m.x - eye.x, dy = m.y - eye.y
        let d = hypot(dx, dy)
        guard d > 0.5 else { return .zero }
        let k = min(d / 50, 1) * 4.5 / d
        return CGVector(dx: dx * k, dy: dy * k)
    }

    func keyboard(_ ctx: inout GraphicsContext) {
        let base = CGRect(x: 32, y: 126, width: 156, height: 40)
        ctx.fill(Path(roundedRect: base, cornerRadius: 9), with: .color(Color(red: 0.24, green: 0.26, blue: 0.30)))
        ctx.fill(Path(roundedRect: base.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: -3), cornerRadius: 9),
                 with: .color(Color(red: 0.36, green: 0.39, blue: 0.44)))

        let keyColor = Color(red: 0.93, green: 0.94, blue: 0.95)
        let pressedColor = Color(red: 0.70, green: 0.73, blue: 0.77)
        let pressed = Set([model.leftKey, model.rightKey].compactMap { $0 })
        var keys = [KeyPos(row: 3, col: 0)]
        for (row, n) in KeyLayout.rowCounts.enumerated() {
            for col in 0..<n { keys.append(KeyPos(row: row, col: col)) }
        }
        for k in keys {
            let r = KeyLayout.rect(k)
            let down = pressed.contains(k)
            ctx.fill(Path(roundedRect: down ? r.offsetBy(dx: 0, dy: 1) : r, cornerRadius: 2),
                     with: .color(down ? pressedColor : keyColor))
        }
    }

    /// 爪子中心：按键时落在对应的键上，否则抬起（睡觉时搭在键盘上）
    func pawCenter(left: Bool, key: KeyPos?) -> CGPoint {
        let sx = left ? 80.0 : 140.0
        if let key {
            let r = KeyLayout.rect(key)
            let x = key.row == 3 ? r.midX + (left ? -14 : 14) : r.midX
            return CGPoint(x: x, y: r.midY + 1)
        }
        // 右爪搭在小鼠标上；点击时往下按一点
        if !left && usingMouse {
            let m = miniMouseCenter
            let press = model.mouseLeftDown || model.mouseRightDown ? 2.0 : 0
            return CGPoint(x: m.x - 8, y: m.y - 15 + press)
        }
        return CGPoint(x: sx, y: sleeping ? 136 : 120)
    }

    // MARK: - 小鼠标

    var usingMouse: Bool { t < model.mouseActiveUntil }
    static let padRect = CGRect(x: 190, y: 133, width: 28, height: 34)
    var miniMouseCenter: CGPoint {
        CGPoint(x: Self.padRect.midX + model.miniMouse.dx, y: Self.padRect.midY + 1 + model.miniMouse.dy)
    }

    func miniMouse(_ ctx: inout GraphicsContext) {
        let pad = Self.padRect
        ctx.fill(Path(ellipseIn: CGRect(x: pad.minX - 2, y: pad.maxY - 4, width: pad.width + 4, height: 8)),
                 with: .color(.black.opacity(0.15)))
        ctx.fill(Path(roundedRect: pad, cornerRadius: 6), with: .color(Color(red: 0.36, green: 0.39, blue: 0.44)))

        let c = miniMouseCenter
        let body = CGRect(x: c.x - 9, y: c.y - 13, width: 18, height: 26)
        // 线连到键盘
        var cord = Path()
        cord.move(to: CGPoint(x: c.x, y: body.minY))
        cord.addQuadCurve(to: CGPoint(x: 186, y: 131), control: CGPoint(x: c.x - 2, y: 122))
        ctx.stroke(cord, with: .color(Color(red: 0.24, green: 0.26, blue: 0.30)), lineWidth: 1.5)

        let shell = Color(red: 0.93, green: 0.94, blue: 0.95)
        let pressed = Color(red: 0.70, green: 0.73, blue: 0.77)
        ctx.fill(Path(roundedRect: body, cornerRadius: 9), with: .color(shell))
        // 左右键
        var cg = ctx
        cg.clip(to: Path(roundedRect: body, cornerRadius: 9))
        let half = body.width / 2, top = body.height * 0.42
        if model.mouseLeftDown {
            cg.fill(Path(CGRect(x: body.minX, y: body.minY, width: half, height: top)), with: .color(pressed))
        }
        if model.mouseRightDown {
            cg.fill(Path(CGRect(x: body.midX, y: body.minY, width: half, height: top)), with: .color(pressed))
        }
        var seams = Path()
        seams.move(to: CGPoint(x: body.midX, y: body.minY)); seams.addLine(to: CGPoint(x: body.midX, y: body.minY + top))
        seams.move(to: CGPoint(x: body.minX, y: body.minY + top)); seams.addLine(to: CGPoint(x: body.maxX, y: body.minY + top))
        cg.stroke(seams, with: .color(.black.opacity(0.18)), lineWidth: 1)
        ctx.stroke(Path(roundedRect: body, cornerRadius: 9), with: .color(.black.opacity(0.15)), lineWidth: 1)
    }

    func paw(_ ctx: inout GraphicsContext, left: Bool, key: KeyPos?) {
        let c = pawCenter(left: left, key: key)
        let shoulder = CGPoint(x: left ? 80.0 : 140.0, y: 104)
        let w = 30.0, h = 21.0

        // 前臂：从肩膀伸到爪子
        var arm = Path()
        arm.move(to: shoulder)
        arm.addLine(to: c)
        ctx.stroke(arm, with: .color(th.fur), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        // 手掌
        let r = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        ctx.fill(Path(ellipseIn: r), with: .color(th.fur))
        ctx.fill(Path(ellipseIn: r.insetBy(dx: 5, dy: 6).offsetBy(dx: 0, dy: 3)), with: .color(th.light.opacity(0.6)))
        // 脚趾分隔线
        var toes = Path()
        for dx in [-5.0, 5.0] {
            toes.move(to: CGPoint(x: c.x + dx, y: c.y + h / 2 - 1))
            toes.addLine(to: CGPoint(x: c.x + dx, y: c.y + h / 2 - 6))
        }
        ctx.stroke(toes, with: .color(th.shade), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    func effects(_ ctx: inout GraphicsContext) {
        if sleeping {
            for i in 0..<3 {
                let phase = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = 184 + phase * 22
                let y = 34 - phase * 30
                let size = 10 + phase * 8
                let text = Text("z").font(.system(size: size, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.45, green: 0.55, blue: 0.75).opacity(1 - phase))
                ctx.draw(text, at: CGPoint(x: x, y: y))
            }
        }

        // 点鼠标时的冲击线
        if usingMouse && (model.mouseLeftDown || model.mouseRightDown) {
            let m = miniMouseCenter
            var p = Path()
            // 画在鼠标下方，避免超出窗口右边缘
            for (a, b) in [((m.x - 7, m.y + 15), (m.x - 10, m.y + 20)),
                           ((m.x, m.y + 16), (m.x, m.y + 21)),
                           ((m.x + 7, m.y + 15), (m.x + 10, m.y + 20))] {
                p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1))
            }
            ctx.stroke(p, with: .color(Color.orange.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // 被 rua 时冒爱心
        if model.isPetted {
            let spots: [(Double, Double)] = [(38, 44), (182, 50), (170, 30)]
            for (i, spot) in spots.enumerated() {
                let phase = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let center = CGPoint(x: spot.0 + sin(phase * 7 + Double(i)) * 3, y: spot.1 - phase * 26)
                var c = ctx
                c.opacity = 1 - phase
                c.fill(heart(at: center, size: 5 + phase * 2), with: .color(Color(red: 1, green: 0.42, blue: 0.55)))
            }
        }

        // 爪子拍下去时的冲击线
        if mood == .excited || mood == .typing {
            let lines = mood == .excited ? 3 : 2
            for (left, key) in [(true, model.leftKey), (false, model.rightKey)] {
                guard let key else { continue }
                let pc = pawCenter(left: left, key: key)
                let cx = pc.x, cy = pc.y - 2
                var p = Path()
                for i in 0..<lines {
                    let ang = Double.pi * (0.92 + 0.22 * Double(i) / Double(max(lines - 1, 1)))
                    let a = CGPoint(x: cx + cos(ang) * 19, y: cy + sin(ang) * 12)
                    let b = CGPoint(x: cx + cos(ang) * 26, y: cy + sin(ang) * 17)
                    p.move(to: a); p.addLine(to: b)
                    p.move(to: CGPoint(x: 2 * cx - a.x, y: a.y)); p.addLine(to: CGPoint(x: 2 * cx - b.x, y: b.y))
                }
                ctx.stroke(p, with: .color(Color.orange.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    func heart(at c: CGPoint, size s: Double) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - s, y: c.y - s / 2, width: s, height: s))
        p.addEllipse(in: CGRect(x: c.x, y: c.y - s / 2, width: s, height: s))
        p.move(to: CGPoint(x: c.x - s * 0.98, y: c.y + s * 0.15))
        p.addLine(to: CGPoint(x: c.x + s * 0.98, y: c.y + s * 0.15))
        p.addLine(to: CGPoint(x: c.x, y: c.y + s * 1.25))
        p.closeSubpath()
        return p
    }
}

import AppKit
import SwiftUI

let args = CommandLine.arguments

if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    // 开发用：把各种状态渲染成 PNG，方便检查画面
    MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: args[i + 1])) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor
enum Snapshot {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 截图时间固定为 t = 1.0
        let D = KeyPos(row: 1, col: 2), I = KeyPos(row: 0, col: 7)
        let cases: [(String, (CatModel) -> Void)] = [
            ("idle", { m in m.force(mood: .idle, left: nil, right: nil); m.mouse = CGPoint(x: 215, y: 10) }),
            ("typing", { m in
                m.force(mood: .typing, left: D, right: nil)
                m.letters = [FloatingLetter(text: "d", key: D, born: 0.8)]
                m.typedLine = "hello cat"; m.lastTypedAt = 0.9 }),
            ("excited", { m in
                m.force(mood: .excited, left: nil, right: I)
                m.letters = [FloatingLetter(text: "a", key: KeyPos(row: 1, col: 0), born: 0.55),
                             FloatingLetter(text: "i", key: I, born: 0.85)]
                m.typedLine = "meow meow"; m.lastTypedAt = 0.9 }),
            ("mouse", { m in
                m.force(mood: .idle, left: nil, right: nil)
                m.mouseActiveUntil = 2; m.mouseLeftDown = true
                m.miniMouse = CGVector(dx: 3, dy: -2); m.mouse = CGPoint(x: 230, y: 160) }),
            ("petted", { m in m.force(mood: .idle, left: nil, right: nil); m.isPetted = true }),
            ("sleeping", { m in m.force(mood: .sleeping, left: nil, right: nil) }),
            ("permission", { m in m.force(mood: .idle, left: nil, right: nil); m.needsPermission = true }),
        ]
        for theme in CatTheme.presets {
            for (name, setup) in cases {
                if theme.id != "blue" && name != "typing" { continue }
                let model = CatModel()
                model.theme = theme
                setup(model)
                let view = CatView(model: model, fixedTime: 1.0)
                    .frame(width: CatView.designSize.width * 2, height: CatView.designSize.height * 2)
                    .background(Color(white: 0.97))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let cg = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let url = dir.appendingPathComponent("\(theme.id)-\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print(url.path)
            }
        }
    }
}

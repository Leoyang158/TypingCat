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
        let cases: [(String, CatMood, Bool, Bool)] = [
            ("idle", .idle, false, false),
            ("typing", .typing, true, false),
            ("excited", .excited, false, true),
            ("sleeping", .sleeping, false, false),
            ("permission", .idle, false, false),
        ]
        for theme in CatTheme.presets {
            for (name, mood, l, r) in cases {
                if theme.id != "blue" && name != "typing" { continue }
                let model = CatModel()
                model.theme = theme
                model.force(mood: mood, left: l, right: r)
                model.needsPermission = name == "permission"
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

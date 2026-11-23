import AppKit
import SwiftUI

/// 透明、无边框、不抢焦点的浮动面板
final class CatPanel: NSPanel {
    init(model: CatModel, menuProvider: @escaping () -> NSMenu, onClick: @escaping () -> Void) {
        super.init(contentRect: NSRect(origin: .zero, size: CatView.designSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let host = DraggableHostingView(rootView: CatView(model: model))
        host.menuProvider = menuProvider
        host.onClick = onClick
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 拖动猫咪移动窗口；单击（没有拖动）触发 onClick；右键弹出菜单
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var menuProvider: (() -> NSMenu)?
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var moved = false

        // 自己跟踪拖动，这样能区分"单击"和"拖动"
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let now = NSEvent.mouseLocation
            let dx = now.x - startMouse.x, dy = now.y - startMouse.y
            if e.type == .leftMouseUp { break }
            if !moved && hypot(dx, dy) < 3 { continue }
            moved = true
            window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
        if !moved { onClick?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

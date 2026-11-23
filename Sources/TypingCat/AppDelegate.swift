import AppKit
import ServiceManagement

enum CatSize: String, CaseIterable {
    case small, medium, large
    var title: String { switch self { case .small: "小"; case .medium: "中"; case .large: "大" } }
    var scale: CGFloat { switch self { case .small: 0.7; case .medium: 1.0; case .large: 1.45 } }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = CatModel()
    let keyboard = KeyboardMonitor()
    var panel: CatPanel!
    var statusItem: NSStatusItem!
    var hasPermission = false
    let defaults = UserDefaults.standard

    var size: CatSize {
        get { CatSize(rawValue: defaults.string(forKey: "size") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "size"); applySize() }
    }
    var clickThrough: Bool {
        get { defaults.bool(forKey: "clickThrough") }
        set { defaults.set(newValue, forKey: "clickThrough"); panel.ignoresMouseEvents = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = CatPanel(model: model,
                         menuProvider: { [weak self] in self?.buildMenu() ?? NSMenu() },
                         onClick: { [weak self] in self?.catClicked() })
        panel.delegate = self
        panel.ignoresMouseEvents = clickThrough
        applySize()
        restorePosition()
        if defaults.object(forKey: "visible") as? Bool ?? true { panel.orderFrontRegardless() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "TypingCat")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        DebugLog.write("启动 \(Bundle.main.bundlePath)")
        keyboard.onKey = { [weak self] in self?.model.keyPressed() }
        if !KeyboardMonitor.hasAnyPermission { KeyboardMonitor.requestPermission() }
        keyboard.start { [weak self] status in
            guard let self else { return }
            self.hasPermission = status == .running
            self.model.needsPermission = !self.hasPermission
            if self.hasPermission { self.guideWindow?.close() }
        }
    }

    // MARK: - 权限引导

    var guideWindow: NSWindow?

    /// 没权限时点击猫：打开系统设置，并给一个"授权后重启"的按钮
    func catClicked() {
        guard !hasPermission else { return }
        openPermission()
    }

    @objc func openPermission() {
        KeyboardMonitor.requestPermission()
        KeyboardMonitor.openSettings()
        showGuide()
    }

    func showGuide() {
        if let w = guideWindow { w.orderFrontRegardless(); return }
        let label = NSTextField(wrappingLabelWithString:
            "1. 在「隐私与安全性 → 输入监控」里打开 TypingCat\n   （列表里没有的话，点「+」添加 TypingCat.app）\n2. 打开后点下面的按钮重新启动")
        label.font = .systemFont(ofSize: 13)
        let button = NSButton(title: "我已授权，重新启动", target: self, action: #selector(relaunch))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "开启键盘权限"
        w.contentView = stack
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.center()
        guideWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.orderFrontRegardless()
    }

    /// 运行中的进程往往感知不到新授权，所以拉起一个新实例再退出自己
    @objc func relaunch() {
        DebugLog.write("用户请求重新启动")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error { DebugLog.write("重启失败：\(error.localizedDescription)") }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - 窗口

    func applySize() {
        guard let panel else { return }
        let s = size.scale
        var f = panel.frame
        let newSize = NSSize(width: CatView.designSize.width * s, height: CatView.designSize.height * s)
        // 保持底部中点不动
        f.origin.x += (f.width - newSize.width) / 2
        f.size = newSize
        panel.setFrame(f, display: true)
    }

    func restorePosition() {
        if let s = defaults.string(forKey: "origin") {
            let p = NSPointFromString(s)
            let frame = NSRect(origin: p, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrameOrigin(p)
                return
            }
        }
        // 默认放在主屏右下角
        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 24, y: vf.minY + 12))
        }
    }

    func windowDidMove(_ notification: Notification) {
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "origin")
    }

    // MARK: - 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items { item.menu?.removeItem(item); menu.addItem(item) }
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()

        if hasPermission {
            let ok = NSMenuItem(title: "✅ 键盘监听中", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            m.addItem(ok)
        } else {
            m.addItem(item("⚠️ 需要「输入监控」权限，点此打开设置…", #selector(openPermission)))
            m.addItem(item("我已授权，重新启动 TypingCat", #selector(relaunch)))
        }
        m.addItem(.separator())

        let count = NSMenuItem(title: "今天已敲 \(model.todayCount) 下", action: nil, keyEquivalent: "")
        count.isEnabled = false
        m.addItem(count)
        m.addItem(.separator())

        m.addItem(item(panel.isVisible ? "隐藏猫咪" : "显示猫咪", #selector(toggleVisible), key: "h"))

        // 毛色
        let colorMenu = NSMenu()
        for theme in CatTheme.presets {
            let it = item(theme.name, #selector(pickTheme(_:)))
            it.representedObject = theme.id
            it.state = model.theme.id == theme.id ? .on : .off
            it.image = swatch(theme)
            colorMenu.addItem(it)
        }
        colorMenu.addItem(.separator())
        let custom = item("自定义颜色…", #selector(pickCustomColor))
        custom.state = model.theme.id == "custom" ? .on : .off
        colorMenu.addItem(custom)
        let colorItem = NSMenuItem(title: "毛色", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        m.addItem(colorItem)

        // 大小
        let sizeMenu = NSMenu()
        for s in CatSize.allCases {
            let it = item(s.title, #selector(pickSize(_:)))
            it.representedObject = s.rawValue
            it.state = size == s ? .on : .off
            sizeMenu.addItem(it)
        }
        let sizeItem = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        m.addItem(sizeItem)

        let ct = item("鼠标穿透（不可拖动）", #selector(toggleClickThrough))
        ct.state = clickThrough ? .on : .off
        m.addItem(ct)

        let login = item("开机自动启动", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)

        m.addItem(.separator())
        m.addItem(item("退出 TypingCat", #selector(quit), key: "q"))
        return m
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    private func swatch(_ theme: CatTheme) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            NSColor(theme.fur).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).stroke()
            return true
        }
    }

    // MARK: - 动作

    @objc func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        defaults.set(panel.isVisible, forKey: "visible")
    }

    @objc func pickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let t = CatTheme.presets.first(where: { $0.id == id }) else { return }
        model.setTheme(t)
    }

    @objc func pickCustomColor() {
        let cp = NSColorPanel.shared
        cp.showsAlpha = false
        cp.setTarget(self)
        cp.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        cp.orderFrontRegardless()
    }

    @objc func customColorChanged(_ sender: NSColorPanel) {
        model.setCustomFur(sender.color)
    }

    @objc func pickSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let s = CatSize(rawValue: raw) { size = s }
    }

    @objc func toggleClickThrough() { clickThrough.toggle() }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "无法设置开机启动"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

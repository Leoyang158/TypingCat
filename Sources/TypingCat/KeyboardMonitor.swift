import AppKit
import ApplicationServices
import CoreGraphics

/// 一次按键：键码 + 产生的字符（只用于屏幕上短暂显示，不保存）
struct KeyInfo {
    var keyCode: Int
    var chars: String
    var command: Bool
}

/// 全局键盘监听（只监听、不拦截）。
/// 按键信息只交给猫咪做动画和短暂显示，不写入磁盘、不上传。
///
/// 两条路径，满足任意一种权限即可：
/// - 「输入监控」→ CGEventTap（listen-only）
/// - 「辅助功能」→ NSEvent 全局监听
final class KeyboardMonitor {
    enum Status { case needsPermission, running }

    var onKey: ((KeyInfo) -> Void)?
    private(set) var status: Status = .needsPermission
    private var received = 0
    private var tap: CFMachPort?
    private var globalMonitor: Any?
    private var retryTimer: Timer?
    private var loggedNoPermission = false

    static var hasListenPermission: Bool { CGPreflightListenEventAccess() }
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasAnyPermission: Bool { hasListenPermission || hasAccessibility }

    /// 请求输入监控权限（首次会让 TypingCat 出现在设置列表里）
    static func requestPermission() { _ = CGRequestListenEventAccess() }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 启动；没有权限时每 2 秒重试，直到拿到任一权限。
    func start(onStatusChange: @escaping (Status) -> Void) {
        if tryStart() { onStatusChange(.running); return }
        onStatusChange(.needsPermission)
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.tryStart() {
                t.invalidate()
                onStatusChange(.running)
            }
        }
    }

    private func tryStart() -> Bool {
        if status == .running { return true }
        if KeyboardMonitor.hasListenPermission, startEventTap() {
            DebugLog.write("键盘监听已启动（输入监控 / CGEventTap）")
        } else if KeyboardMonitor.hasAccessibility, startGlobalMonitor() {
            DebugLog.write("键盘监听已启动（辅助功能 / NSEvent）")
        } else {
            if !loggedNoPermission {
                DebugLog.write("未授权：输入监控=\(KeyboardMonitor.hasListenPermission) 辅助功能=\(KeyboardMonitor.hasAccessibility)")
                loggedNoPermission = true
            }
            return false
        }
        status = .running
        return true
    }

    fileprivate func handleKey(_ info: KeyInfo) {
        received += 1
        if received == 1 { DebugLog.write("收到第一次按键事件 ✅") }
        onKey?(info)
    }

    // MARK: - 路径 1：CGEventTap

    private func startEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                case .keyDown:
                    // 长按自动重复不算
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        var len = 0
                        var buf = [UniChar](repeating: 0, count: 8)
                        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &buf)
                        let info = KeyInfo(
                            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                            chars: String(utf16CodeUnits: buf, count: len),
                            command: event.flags.contains(.maskCommand))
                        DispatchQueue.main.async { monitor.handleKey(info) }
                    }
                default: break
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            DebugLog.write("有输入监控权限，但 CGEvent.tapCreate 失败")
            return false
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - 路径 2：NSEvent 全局监听

    private func startGlobalMonitor() -> Bool {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard !e.isARepeat else { return }
            self?.handleKey(KeyInfo(keyCode: Int(e.keyCode), chars: e.characters ?? "",
                                    command: e.modifierFlags.contains(.command)))
        }
        return globalMonitor != nil
    }
}

/// 诊断日志：~/Library/Logs/TypingCat.log（不记录任何按键内容）
enum DebugLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TypingCat.log")
    static func write(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

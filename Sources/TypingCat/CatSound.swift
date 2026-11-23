import AVFoundation

/// 用代码合成的猫叫和呼噜声（不依赖任何音频文件）
final class CatSound {
    private let engine = AVAudioEngine()
    private let meowNode = AVAudioPlayerNode()
    private let purrNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var purrBuffer: AVAudioPCMBuffer?
    private var fadeTimer: Timer?
    private var lastMeow: TimeInterval = 0

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "soundOn")
            if !enabled { stopPurr(immediately: true) }
        }
    }

    init() {
        enabled = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true
        engine.attach(meowNode)
        engine.attach(purrNode)
        engine.connect(meowNode, to: engine.mainMixerNode, format: format)
        engine.connect(purrNode, to: engine.mainMixerNode, format: format)
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            engine.prepare()
            try engine.start()
            return true
        } catch {
            DebugLog.write("音频引擎启动失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 喵

    /// cooldown：距上次叫多久之内不再叫
    func meow(cooldown: TimeInterval = 0.6) {
        guard enabled else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastMeow > cooldown, ensureRunning() else { return }
        lastMeow = now
        let buf = makeMeow()
        meowNode.scheduleBuffer(buf, at: nil, options: .interrupts)
        meowNode.play()
    }

    private func makeMeow() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let dur = 0.7 * Double.random(in: 0.85...1.15)
        let ps = Double.random(in: 0.9...1.15)          // 每次音高略有不同
        let n = Int(dur * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]

        func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

        var phase = 0.0
        var peak = 0.0
        var samples = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr, u = t / dur
            // 音高：先上扬再下滑，"mi-a-ow"
            var f0 = u < 0.3 ? lerp(520, 820, ease(u / 0.3)) : lerp(820, 420, ease((u - 0.3) / 0.7))
            f0 *= ps * (1 + 0.015 * sin(2 * .pi * 6 * t))
            // 共振峰：i → a → u
            let f1 = u < 0.35 ? lerp(450, 950, ease(u / 0.35)) : lerp(950, 550, ease((u - 0.35) / 0.65))
            let f2 = u < 0.35 ? lerp(2300, 1450, ease(u / 0.35)) : lerp(1450, 900, ease((u - 0.35) / 0.65))
            phase += 2 * .pi * f0 / sr
            var s = 0.0
            for k in 1...20 {
                let fk = Double(k) * f0
                let a1 = exp(-pow((fk - f1) / 260, 2))
                let a2 = 0.6 * exp(-pow((fk - f2) / 420, 2))
                s += (a1 + a2 + 0.04) / pow(Double(k), 0.7) * sin(Double(k) * phase)
            }
            s += Double.random(in: -1...1) * 0.03          // 一点气声
            let attack = min(1, u / 0.08)
            let release = u > 0.65 ? max(0, (1 - u) / 0.35) : 1
            s *= pow(attack * release, 1.5)
            samples[i] = s
            peak = max(peak, abs(s))
        }
        let gain = 0.45 / max(peak, 1e-6)
        for i in 0..<n { out[i] = Float(samples[i] * gain) }
        return buf
    }

    // MARK: - 呼噜

    func startPurr() {
        guard enabled, ensureRunning() else { return }
        fadeTimer?.invalidate()
        if purrBuffer == nil { purrBuffer = makePurr() }
        if !purrNode.isPlaying {
            purrNode.volume = 0
            purrNode.scheduleBuffer(purrBuffer!, at: nil, options: .loops)
            purrNode.play()
        }
        fade(to: 1)
    }

    func stopPurr(immediately: Bool = false) {
        guard purrNode.isPlaying else { return }
        if immediately {
            fadeTimer?.invalidate()
            purrNode.stop()
            return
        }
        fade(to: 0) { [weak self] in self?.purrNode.stop() }
    }

    private func fade(to target: Float, then done: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let v = self.purrNode.volume
            let step: Float = 0.08
            if abs(v - target) <= step {
                self.purrNode.volume = target
                t.invalidate()
                done?()
            } else {
                self.purrNode.volume = v + (target > v ? step : -step)
            }
        }
    }

    /// 1.2 秒可无缝循环的呼噜声：低通噪声 + 低频音，按 25Hz 脉动，并随"呼吸"起伏
    private func makePurr() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let dur = 1.2
        let n = Int(dur * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        var lp = 0.0, lp2 = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            lp += 0.05 * (Double.random(in: -1...1) - lp)
            lp2 += 0.05 * (lp - lp2)
            let pulse = pow(max(0, sin(2 * .pi * 25 * t)), 2)
            let breath = 0.55 + 0.45 * pow(sin(.pi * t / dur), 2)
            let s = (lp2 * 6 + 0.35 * sin(2 * .pi * 50 * t)) * pulse * breath
            out[i] = Float(max(-1, min(1, s * 0.5)))
        }
        return buf
    }
}

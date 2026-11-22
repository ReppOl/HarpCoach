import Foundation
import AVFoundation
import Combine

final class ToneSynth {
    private let lock = NSLock()
    private var active = false
    private var elapsed: Double = 0
    private var duration: Double = 1.0
    private var startFreq: Double = 440
    private var targetFreq: Double = 440
    private var isGlide = false
    private var phase: Double = 0
    private var sampleRate: Double = 44100

    func configure(sampleRate: Double) {
        lock.lock()
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        lock.unlock()
    }

    func triggerNote(freq: Double, duration: Double = 1.3) {
        lock.lock()
        self.startFreq = freq
        self.targetFreq = freq
        self.isGlide = false
        self.duration = duration
        self.elapsed = 0
        self.phase = 0
        self.active = true
        lock.unlock()
    }

    func triggerBendGlide(startFreq: Double, targetFreq: Double) {
        lock.lock()
        self.startFreq = startFreq
        self.targetFreq = targetFreq
        self.isGlide = true
        self.duration = 2.2
        self.elapsed = 0
        self.phase = 0
        self.active = true
        lock.unlock()
    }

    func nextSample() -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard active else { return 0 }
        let dt = 1.0 / sampleRate
        elapsed += dt
        if elapsed >= duration {
            active = false
            return 0
        }

        let currentFreq: Double
        if !isGlide {
            currentFreq = startFreq
        } else {
            // 0.0-0.45s: чистая нота, 0.45-0.95s: спуск в бэнд, 0.95-1.75s: удержание, 1.75-2.2s: возврат
            if elapsed < 0.45 {
                currentFreq = startFreq
            } else if elapsed < 0.95 {
                let t = (elapsed - 0.45) / 0.50
                currentFreq = startFreq + (targetFreq - startFreq) * t
            } else if elapsed < 1.75 {
                currentFreq = targetFreq
            } else {
                let t = min(1.0, (elapsed - 1.75) / 0.35)
                currentFreq = targetFreq + (startFreq - targetFreq) * t
            }
        }

        phase += 2.0 * Double.pi * currentFreq * dt
        if phase > 2.0 * Double.pi {
            phase.formTruncatingRemainder(dividingBy: 2.0 * Double.pi)
        }

        // Мягкий тембр с гармониками, похожий на язычковый инструмент
        let wave = 0.62 * sin(phase)
            + 0.22 * sin(2.0 * phase)
            + 0.11 * sin(3.0 * phase)
            + 0.05 * sin(4.0 * phase)

        // Плавная атака и затухание без щелчков
        let fadeIn = min(1.0, elapsed / 0.04)
        let fadeOut = min(1.0, (duration - elapsed) / 0.08)
        let env = max(0.0, min(fadeIn, fadeOut))

        return Float(wave * env * 0.35)
    }
}

final class HarpAudioEngine: ObservableObject {
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var currentFreq: Double = 0
    @Published var currentRms: Float = 0
    @Published var isPlayingReference = false
    @Published var selectedKey: HarmonicaKey = .C {
        didSet {
            let range = HarpLayout.freqRange(for: selectedKey)
            stateLock.lock()
            freqRange = range
            stateLock.unlock()
        }
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let synth = ToneSynth()
    private let analysisQueue = DispatchQueue(label: "com.harpcoach.yin", qos: .userInteractive)
    private let stateLock = NSLock()

    private var freqRange: (min: Double, max: Double) = HarpLayout.freqRange(for: .C)
    private var isPlayingRefInternal = false
    private var sampleBuffer: [Float] = []
    private var smoothedFreq: Double = 0
    private var silentChunks = 0
    private var stopRefWorkItem: DispatchWorkItem?

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start(completion: (() -> Void)? = nil) {
        let handleGrant: (Bool) -> Void = { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.permissionDenied = false
                    self.setupAndStartEngine()
                    completion?()
                } else {
                    self.permissionDenied = true
                }
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handleGrant)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handleGrant)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        currentFreq = 0
        currentRms = 0
        smoothedFreq = 0
        sampleBuffer.removeAll()
    }

    func playCleanNote(freq: Double) {
        ensureEngineRunning { [weak self] in
            guard let self = self else { return }
            self.beginReferencePlayback(duration: 1.35)
            self.synth.triggerNote(freq: freq, duration: 1.3)
        }
    }

    func playBendExample(cleanFreq: Double, bendFreq: Double) {
        ensureEngineRunning { [weak self] in
            guard let self = self else { return }
            self.beginReferencePlayback(duration: 2.3)
            self.synth.triggerBendGlide(startFreq: cleanFreq, targetFreq: bendFreq)
        }
    }

    private func ensureEngineRunning(_ action: @escaping () -> Void) {
        if isRunning {
            action()
        } else {
            start {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: action)
            }
        }
    }

    private func beginReferencePlayback(duration: Double) {
        stopRefWorkItem?.cancel()
        stateLock.lock()
        isPlayingRefInternal = true
        stateLock.unlock()

        DispatchQueue.main.async {
            self.isPlayingReference = true
            self.currentFreq = 0
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            self.isPlayingRefInternal = false
            self.stateLock.unlock()
            DispatchQueue.main.async {
                self.isPlayingReference = false
            }
        }
        stopRefWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func setupAndStartEngine() {
        if isRunning { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)

            let outputSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let sr = outputSampleRate > 0 ? outputSampleRate : 44100.0
            synth.configure(sampleRate: sr)

            if sourceNode == nil {
                let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
                let node = AVAudioSourceNode(format: monoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                    guard let self = self else { return noErr }
                    let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                    for frame in 0..<Int(frameCount) {
                        let sample = self.synth.nextSample()
                        for buffer in ablPointer {
                            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                                data[frame] = sample
                            }
                        }
                    }
                    return noErr
                }
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: monoFormat)
                sourceNode = node
            }

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else { return }

            inputNode.removeTap(onBus: 0)
            let captureRate = inputFormat.sampleRate
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self,
                      let channelData = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
                self.analysisQueue.async {
                    self.processSamples(samples, sampleRate: captureRate)
                }
            }

            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            print("Audio start error: \(error.localizedDescription)")
        }
    }

    private func processSamples(_ incoming: [Float], sampleRate: Double) {
        stateLock.lock()
        let muted = isPlayingRefInternal
        let range = freqRange
        stateLock.unlock()

        if muted {
            sampleBuffer.removeAll(keepingCapacity: true)
            smoothedFreq = 0
            return
        }

        // Расчёт громкости (RMS) и порог шума (Noise Gate)
        var sumSq: Float = 0
        for s in incoming { sumSq += s * s }
        let rms = sqrt(sumSq / Float(max(1, incoming.count)))

        guard rms > 0.008 else {
            silentChunks += 1
            if silentChunks > 4 {
                smoothedFreq = 0
                DispatchQueue.main.async {
                    self.currentFreq = 0
                    self.currentRms = rms
                }
            }
            return
        }
        silentChunks = 0

        sampleBuffer.append(contentsOf: incoming)
        let windowSize = 2048
        if sampleBuffer.count > windowSize {
            sampleBuffer.removeFirst(sampleBuffer.count - windowSize)
        }
        guard sampleBuffer.count == windowSize else { return }

        if let detected = detectPitchYIN(buffer: sampleBuffer, sampleRate: sampleRate, minFreq: range.min, maxFreq: range.max) {
            if smoothedFreq > 0 {
                let centsJump = abs(1200.0 * log2(detected / smoothedFreq))
                if centsJump < 130 {
                    smoothedFreq = smoothedFreq * 0.62 + detected * 0.38
                } else {
                    smoothedFreq = detected
                }
            } else {
                smoothedFreq = detected
            }

            let outFreq = smoothedFreq
            DispatchQueue.main.async {
                self.currentFreq = outFreq
                self.currentRms = rms
            }
        }
    }

    /// Алгоритм YIN для точного определения основного тона гармошки без скачков по октавам
    private func detectPitchYIN(buffer: [Float], sampleRate: Double, minFreq: Double, maxFreq: Double) -> Double? {
        let halfSize = buffer.count / 2
        let minTau = max(8, Int(sampleRate / maxFreq))
        let maxTau = min(halfSize - 1, Int(sampleRate / minFreq))
        guard minTau < maxTau else { return nil }

        var diff = [Float](repeating: 0, count: maxTau + 1)
        for tau in 1...maxTau {
            var sum: Float = 0
            for i in 0..<halfSize {
                let d = buffer[i] - buffer[i + tau]
                sum += d * d
            }
            diff[tau] = sum
        }

        var cmndf = [Float](repeating: 1, count: maxTau + 1)
        var runningSum: Float = 0
        for tau in 1...maxTau {
            runningSum += diff[tau]
            if runningSum > 0 {
                cmndf[tau] = diff[tau] * Float(tau) / runningSum
            }
        }

        let threshold: Float = 0.14
        var bestTau = -1
        for tau in minTau...maxTau {
            if cmndf[tau] < threshold {
                var t = tau
                while t + 1 <= maxTau && cmndf[t + 1] < cmndf[t] {
                    t += 1
                }
                bestTau = t
                break
            }
        }

        if bestTau == -1 {
            var minVal: Float = 1.0
            for tau in minTau...maxTau {
                if cmndf[tau] < minVal {
                    minVal = cmndf[tau]
                    bestTau = tau
                }
            }
            if minVal > 0.24 { return nil }
        }

        var betterTau = Double(bestTau)
        if bestTau > 1 && bestTau < maxTau {
            let s0 = Double(cmndf[bestTau - 1])
            let s1 = Double(cmndf[bestTau])
            let s2 = Double(cmndf[bestTau + 1])
            let denom = 2.0 * (2.0 * s1 - s2 - s0)
            if abs(denom) > 1e-9 {
                betterTau += (s2 - s0) / denom
            }
        }

        guard betterTau > 0 else { return nil }
        return sampleRate / betterTau
    }
}

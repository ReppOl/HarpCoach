import SwiftUI
import UIKit

@main
struct HarpCoachApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var audio = HarpAudioEngine()
    @State private var completedLessons: Set<Int> = []

    var body: some View {
        TabView {
            TunerView(audio: audio)
                .tabItem {
                    Label("Тюнер", systemImage: "tuningfork")
                }

            LessonsView(audio: audio, completedLessons: $completedLessons)
                .tabItem {
                    Label("Уроки", systemImage: "music.note.list")
                }
        }
        .tint(.orange)
    }
}

// MARK: - Экран Тюнера бэндов

struct TunerView: View {
    @ObservedObject var audio: HarpAudioEngine
    @State private var lockedHole: Int? = 4
    @State private var selectedBendStep: Int = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    keySelector
                    holeSelector

                    if let hole = lockedHole {
                        BendTrackCard(
                            audio: audio,
                            hole: hole,
                            selectedBendStep: $selectedBendStep
                        )
                    } else {
                        AutoTunerCard(audio: audio)
                    }

                    if audio.permissionDenied {
                        Text("Доступ к микрофону запрещён. Включи его в Настройках iPhone → HarpCoach.")
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
            .navigationTitle("HarpCoach")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { audio.toggle() }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(audio.isRunning ? Color.green : Color.gray)
                                .frame(width: 9, height: 9)
                            Text(audio.isRunning ? "Слушаю" : "Старт")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(audio.isRunning ? Color.green.opacity(0.2) : Color.orange.opacity(0.25))
                        .foregroundColor(audio.isRunning ? .green : .orange)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var keySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тональность гармошки")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HarmonicaKey.allCases) { key in
                        let isSelected = audio.selectedKey == key
                        Button(key.displayName) {
                            audio.selectedKey = key
                        }
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 38)
                        .background(isSelected ? Color.orange : Color.white.opacity(0.08))
                        .foregroundColor(isSelected ? .black : .white)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var holeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Отверстие (выбери для тренировки бэнда)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(lockedHole == nil ? "Режим: Авто" : "Включить Авто") {
                    lockedHole = nil
                }
                .font(.caption.bold())
                .foregroundColor(lockedHole == nil ? .orange : .secondary)
            }

            HStack(spacing: 5) {
                ForEach(1...10, id: \.self) { hole in
                    let isSelected = lockedHole == hole
                    let spec = HarpLayout.holeSpec(hole)
                    Button {
                        lockedHole = hole
                        selectedBendStep = min(max(1, selectedBendStep), max(1, spec.bendCount))
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(hole)")
                                .font(.system(size: 15, weight: .bold))
                            Circle()
                                .fill(spec.bendCount > 0 ? (isSelected ? Color.black : Color.orange.opacity(0.8)) : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? Color.orange : Color.white.opacity(0.08))
                        .foregroundColor(isSelected ? .black : .white)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}

struct BendTrackCard: View {
    @ObservedObject var audio: HarpAudioEngine
    let hole: Int
    @Binding var selectedBendStep: Int

    var body: some View {
        let spec = HarpLayout.holeSpec(hole)
        let isDrawBend = spec.bendDirectionIsDraw
        let cleanNote = HarpLayout.note(hole: hole, isDraw: spec.bendCount > 0 ? isDrawBend : true, bendSteps: 0, key: audio.selectedKey)
        let blowNote = HarpLayout.note(hole: hole, isDraw: false, bendSteps: 0, key: audio.selectedKey)
        let drawNote = HarpLayout.note(hole: hole, isDraw: true, bendSteps: 0, key: audio.selectedKey)
        let maxBends = spec.bendCount
        let activeStep = min(max(1, selectedBendStep), max(1, maxBends))
        let targetNote = maxBends > 0
            ? HarpLayout.note(hole: hole, isDraw: isDrawBend, bendSteps: activeStep, key: audio.selectedKey)
            : cleanNote

        let centsFromClean: Double? = audio.currentFreq > 0
            ? (HarpLayout.freqToMidi(audio.currentFreq) - Double(cleanNote.midi)) * 100.0
            : nil

        let targetCents = maxBends > 0 ? -Double(activeStep) * 100.0 : 0.0
        let status = bendStatus(cents: centsFromClean, target: targetCents, hasBends: maxBends > 0)

        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Отверстие \(hole) • Ключ \(audio.selectedKey.displayName)")
                        .font(.headline)
                    Text("Выдох: \(blowNote.noteName)   •   Вдох: \(drawNote.noteName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(targetNote.tabLabel)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
            }

            if maxBends > 1 {
                HStack(spacing: 8) {
                    ForEach(1...maxBends, id: \.self) { step in
                        let note = HarpLayout.note(hole: hole, isDraw: isDrawBend, bendSteps: step, key: audio.selectedKey)
                        Button {
                            selectedBendStep = step
                        } label: {
                            Text("\(note.tabLabel) (\(note.noteName))")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(activeStep == step ? Color.orange.opacity(0.25) : Color.white.opacity(0.06))
                                .foregroundColor(activeStep == step ? .orange : .white)
                                .cornerRadius(8)
                        }
                    }
                }
            }

            // Визуальная дорожка бэнда
            if maxBends > 0 {
                BendScaleBar(
                    maxBends: maxBends,
                    targetStep: activeStep,
                    currentCents: centsFromClean
                )
            } else {
                Text("На отверстии \(hole) нет полутоновых бэндов — отрабатывай чистые одиночные ноты.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
            }

            // Подсказка в реальном времени
            VStack(spacing: 4) {
                Text(status.text)
                    .font(.title3.bold())
                    .foregroundColor(status.color)
                if let c = centsFromClean {
                    Text(String(format: "%+.0f центов от чистой ноты  •  %.1f Гц", c, audio.currentFreq))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(audio.isRunning ? "Сыграй в микрофон..." : "Нажми «Старт» сверху, чтобы включить тюнер")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Кнопки прослушивания эталона
            HStack(spacing: 12) {
                Button {
                    audio.playCleanNote(freq: cleanNote.frequency)
                } label: {
                    Label("Чистая \(cleanNote.noteName)", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                if maxBends > 0 {
                    Button {
                        audio.playBendExample(cleanFreq: cleanNote.frequency, bendFreq: targetNote.frequency)
                    } label: {
                        Label("Бэнд \(targetNote.tabLabel)", systemImage: "waveform.path")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.06))
        .cornerRadius(20)
    }

    private func bendStatus(cents: Double?, target: Double, hasBends: Bool) -> (text: String, color: Color) {
        guard let c = cents else { return ("Жду звук", .secondary) }
        if !hasBends {
            return abs(c) <= 20 ? ("Точно в ноту!", .green) : (c > 0 ? "Чуть выше" : "Чуть ниже", .yellow)
        }
        if abs(c - target) <= 18 {
            return ("Точно в бэнд!", .green)
        } else if abs(c) <= 20 {
            return ("Чистая нота — тяни вниз", .cyan)
        } else if c > target + 18 && c < 30 {
            return ("Недожал — дави ещё ниже ↓", .orange)
        } else if c < target - 18 && c > target - 120 {
            return ("Пережал — чуть ослабь ↑", .red)
        } else {
            return ("Другая нота", .secondary)
        }
    }
}

struct BendScaleBar: View {
    let maxBends: Int
    let targetStep: Int
    let currentCents: Double?

    var body: some View {
        let minCents = -Double(maxBends) * 100.0 - 40.0
        let maxCents = 40.0
        let totalRange = maxCents - minCents

        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let xFor: (Double) -> CGFloat = { cents in
                    // Слева — глубже бэнд, справа — чистая нота (0)
                    let clamped = min(max(cents, minCents), maxCents)
                    let ratio = (clamped - minCents) / totalRange
                    return CGFloat(ratio) * w
                }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.45))
                        .frame(height: 44)

                    // Зелёная целевая зона
                    let targetCents = -Double(targetStep) * 100.0
                    let zoneLeft = xFor(targetCents - 18)
                    let zoneRight = xFor(targetCents + 18)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.32))
                        .frame(width: max(12, zoneRight - zoneLeft), height: 44)
                        .offset(x: zoneLeft)

                    // Метки: чистая нота и каждый шаг бэнда
                    ForEach(0...maxBends, id: \.self) { step in
                        let c = -Double(step) * 100.0
                        Rectangle()
                            .fill(step == targetStep ? Color.green : Color.white.opacity(0.35))
                            .frame(width: 2, height: 44)
                            .offset(x: xFor(c) - 1)
                    }

                    // Живой курсор
                    if let c = currentCents, c >= minCents - 30 && c <= maxCents + 30 {
                        let inZone = abs(c - targetCents) <= 18
                        Circle()
                            .fill(inZone ? Color.green : Color.orange)
                            .frame(width: 20, height: 20)
                            .shadow(color: (inZone ? Color.green : Color.orange).opacity(0.8), radius: 6)
                            .offset(x: xFor(c) - 10)
                            .animation(.easeOut(duration: 0.08), value: c)
                    }
                }
            }
            .frame(height: 44)

            HStack {
                Text("Глубже (-\(maxBends) пт)")
                Spacer()
                Text("Чистая (0)")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}

struct AutoTunerCard: View {
    @ObservedObject var audio: HarpAudioEngine

    var body: some View {
        let match = HarpLayout.closestNote(freq: audio.currentFreq, key: audio.selectedKey)

        VStack(spacing: 16) {
            Text("Автоопределение ноты • Ключ \(audio.selectedKey.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let m = match {
                Text(m.note.tabLabel)
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(abs(m.cents) <= 18 ? .green : .orange)
                Text("\(m.note.noteName)  •  \(String(format: "%.1f Гц", audio.currentFreq))")
                    .font(.headline)
                Text(String(format: "%+.0f центов", m.cents))
                    .font(.subheadline.bold())
                    .foregroundColor(abs(m.cents) <= 18 ? .green : .secondary)
            } else {
                Text("—")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(.secondary)
                Text(audio.isRunning ? "Сыграй любую ноту" : "Нажми «Старт» сверху")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.white.opacity(0.06))
        .cornerRadius(20)
    }
}

// MARK: - Экран Уроков

struct LessonsView: View {
    @ObservedObject var audio: HarpAudioEngine
    @Binding var completedLessons: Set<Int>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Тональность занятий")
                        Spacer()
                        Picker("Ключ", selection: $audio.selectedKey) {
                            ForEach(HarmonicaKey.allCases) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Стартовый курс (6 упражнений)") {
                    ForEach(LessonItem.starterLessons) { lesson in
                        NavigationLink {
                            LessonPracticeView(
                                lesson: lesson,
                                audio: audio,
                                isCompleted: completedLessons.contains(lesson.id),
                                onComplete: { completedLessons.insert(lesson.id) }
                            )
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: completedLessons.contains(lesson.id) ? "checkmark.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(completedLessons.contains(lesson.id) ? .green : .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(lesson.title)
                                        .font(.headline)
                                    Text(lesson.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Уроки")
        }
    }
}

struct LessonPracticeView: View {
    let lesson: LessonItem
    @ObservedObject var audio: HarpAudioEngine
    let isCompleted: Bool
    let onComplete: () -> Void

    @State private var holdTime: Double = 0
    @State private var passedNow = false

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        let cleanNote = HarpLayout.note(hole: lesson.hole, isDraw: lesson.isDraw, bendSteps: 0, key: audio.selectedKey)
        let targetNote = HarpLayout.note(hole: lesson.hole, isDraw: lesson.isDraw, bendSteps: lesson.bendSteps, key: audio.selectedKey)
        let centsError: Double? = audio.currentFreq > 0
            ? (HarpLayout.freqToMidi(audio.currentFreq) - Double(targetNote.midi)) * 100.0
            : nil
        let isHit = (centsError != nil) && abs(centsError!) <= lesson.toleranceCents
        let progress = min(1.0, holdTime / lesson.holdSeconds)

        ScrollView {
            VStack(spacing: 18) {
                // Карточка цели
                VStack(spacing: 8) {
                    Text(targetNote.tabLabel)
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(isHit || passedNow ? .green : .orange)
                    Text("Цель: \(targetNote.noteName) • Ключ \(audio.selectedKey.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(18)

                // Инструкция
                VStack(alignment: .leading, spacing: 10) {
                    Text("Как сделать")
                        .font(.headline)
                    Text(lesson.tip)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Text(lesson.vowelCue)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(18)

                // Кнопка прослушать эталон
                Button {
                    if lesson.bendSteps > 0 {
                        audio.playBendExample(cleanFreq: cleanNote.frequency, bendFreq: targetNote.frequency)
                    } else {
                        audio.playCleanNote(freq: targetNote.frequency)
                    }
                } label: {
                    Label("Послушать как должно звучать", systemImage: "speaker.wave.2.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                }

                // Индикатор зачёта
                VStack(spacing: 12) {
                    if passedNow || isCompleted {
                        Label("Упражнение зачтено!", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold())
                            .foregroundColor(.green)
                    } else {
                        Text(feedbackText(centsError: centsError))
                            .font(.headline)
                            .foregroundColor(isHit ? .green : .orange)
                    }

                    ProgressView(value: passedNow ? 1.0 : progress)
                        .tint(.green)
                        .scaleEffect(x: 1, y: 2.2, anchor: .center)

                    Text("Удерживай точную ноту \(String(format: "%.1f", lesson.holdSeconds)) сек")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !audio.isRunning {
                        Button("Включить микрофон для проверки") {
                            audio.start()
                        }
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(18)
            }
            .padding()
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !audio.isRunning { audio.start() }
        }
        .onReceive(timer) { _ in
            guard audio.isRunning, !passedNow else { return }
            if let err = centsError, abs(err) <= lesson.toleranceCents {
                holdTime += 0.05
                if holdTime >= lesson.holdSeconds {
                    passedNow = true
                    onComplete()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } else {
                holdTime = max(0, holdTime - 0.08)
            }
        }
    }

    private func feedbackText(centsError: Double?) -> String {
        guard audio.isRunning else { return "Микрофон выключен" }
        guard let err = centsError else { return "Слушаю — начинай играть" }
        if abs(err) <= lesson.toleranceCents {
            return "Отлично! Держи ровно..."
        } else if err > lesson.toleranceCents {
            return lesson.bendSteps > 0 ? "Выше цели — тяни бэнд глубже ↓" : "Звук выше цели"
        } else {
            return lesson.bendSteps > 0 ? "Пережал — чуть ослабь ↑" : "Звук ниже цели"
        }
    }
}

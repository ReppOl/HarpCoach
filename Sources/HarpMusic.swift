import Foundation

enum HarmonicaKey: String, CaseIterable, Identifiable {
    case G, Ab, A, Bb, B, C, Db, D, Eb, E, F, Fs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .Fs: return "F#"
        default: return rawValue
        }
    }

    /// MIDI-номер ноты 1-го отверстия на выдох (стандартный строй Рихтера)
    var baseMidi: Int {
        switch self {
        case .G:  return 55 // G3 (196 Hz)
        case .Ab: return 56
        case .A:  return 57 // A3 (220 Hz)
        case .Bb: return 58
        case .B:  return 59
        case .C:  return 60 // C4 (261.6 Hz)
        case .Db: return 61
        case .D:  return 62
        case .Eb: return 63
        case .E:  return 64
        case .F:  return 65
        case .Fs: return 66
        }
    }
}

struct HoleSpec: Identifiable {
    let id: Int
    let blowOffset: Int
    let drawOffset: Int
    let drawBends: [Int]
    let blowBends: [Int]

    var hasDrawBends: Bool { !drawBends.isEmpty }
    var hasBlowBends: Bool { !blowBends.isEmpty }
    var bendCount: Int { max(drawBends.count, blowBends.count) }
    var bendDirectionIsDraw: Bool { hasDrawBends }
}

struct HarpNote: Equatable {
    let hole: Int
    let isDraw: Bool
    let bendSteps: Int
    let midi: Int

    var tabLabel: String {
        let dir = isDraw ? "-" : ""
        let bends = String(repeating: "'", count: bendSteps)
        return "\(dir)\(hole)\(bends)"
    }

    var noteName: String {
        HarpLayout.noteName(for: midi)
    }

    var frequency: Double {
        HarpLayout.midiToFreq(Double(midi))
    }
}

struct HarpLayout {
    static let holes: [HoleSpec] = [
        HoleSpec(id: 1,  blowOffset: 0,  drawOffset: 2,  drawBends: [1],        blowBends: []),
        HoleSpec(id: 2,  blowOffset: 4,  drawOffset: 7,  drawBends: [6, 5],     blowBends: []),
        HoleSpec(id: 3,  blowOffset: 7,  drawOffset: 11, drawBends: [10, 9, 8], blowBends: []),
        HoleSpec(id: 4,  blowOffset: 12, drawOffset: 14, drawBends: [13],       blowBends: []),
        HoleSpec(id: 5,  blowOffset: 16, drawOffset: 17, drawBends: [],         blowBends: []),
        HoleSpec(id: 6,  blowOffset: 19, drawOffset: 21, drawBends: [20],       blowBends: []),
        HoleSpec(id: 7,  blowOffset: 24, drawOffset: 23, drawBends: [],         blowBends: []),
        HoleSpec(id: 8,  blowOffset: 28, drawOffset: 26, drawBends: [],         blowBends: [27]),
        HoleSpec(id: 9,  blowOffset: 31, drawOffset: 29, drawBends: [],         blowBends: [30]),
        HoleSpec(id: 10, blowOffset: 36, drawOffset: 33, drawBends: [],         blowBends: [35, 34])
    ]

    private static let noteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    static func midiToFreq(_ midi: Double) -> Double {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }

    static func freqToMidi(_ freq: Double) -> Double {
        69.0 + 12.0 * log2(freq / 440.0)
    }

    static func noteName(for midi: Int) -> String {
        let name = noteNames[((midi % 12) + 12) % 12]
        let octave = (midi / 12) - 1
        return "\(name)\(octave)"
    }

    static func holeSpec(_ hole: Int) -> HoleSpec {
        holes.first(where: { $0.id == hole }) ?? holes[3]
    }

    static func note(hole: Int, isDraw: Bool, bendSteps: Int, key: HarmonicaKey) -> HarpNote {
        let spec = holeSpec(hole)
        let base = key.baseMidi
        let midi: Int
        if isDraw {
            if bendSteps > 0 && bendSteps <= spec.drawBends.count {
                midi = base + spec.drawBends[bendSteps - 1]
            } else {
                midi = base + spec.drawOffset
            }
        } else {
            if bendSteps > 0 && bendSteps <= spec.blowBends.count {
                midi = base + spec.blowBends[bendSteps - 1]
            } else {
                midi = base + spec.blowOffset
            }
        }
        return HarpNote(hole: hole, isDraw: isDraw, bendSteps: bendSteps, midi: midi)
    }

    static func allNotes(for key: HarmonicaKey) -> [HarpNote] {
        var result: [HarpNote] = []
        let base = key.baseMidi
        for spec in holes {
            result.append(HarpNote(hole: spec.id, isDraw: false, bendSteps: 0, midi: base + spec.blowOffset))
            for (idx, off) in spec.blowBends.enumerated() {
                result.append(HarpNote(hole: spec.id, isDraw: false, bendSteps: idx + 1, midi: base + off))
            }
            result.append(HarpNote(hole: spec.id, isDraw: true, bendSteps: 0, midi: base + spec.drawOffset))
            for (idx, off) in spec.drawBends.enumerated() {
                result.append(HarpNote(hole: spec.id, isDraw: true, bendSteps: idx + 1, midi: base + off))
            }
        }
        return result
    }

    static func freqRange(for key: HarmonicaKey) -> (min: Double, max: Double) {
        let minF = midiToFreq(Double(key.baseMidi) - 2.0)
        let maxF = midiToFreq(Double(key.baseMidi) + 38.0)
        return (minF, maxF)
    }

    static func closestNote(freq: Double, key: HarmonicaKey) -> (note: HarpNote, cents: Double)? {
        guard freq > 60 else { return nil }
        let detectedMidi = freqToMidi(freq)
        let candidates = allNotes(for: key)
        var best: HarpNote?
        var bestDiff = Double.greatestFiniteMagnitude
        for candidate in candidates {
            let diff = abs(detectedMidi - Double(candidate.midi))
            if diff < bestDiff {
                bestDiff = diff
                best = candidate
            }
        }
        guard let matched = best else { return nil }
        let cents = (detectedMidi - Double(matched.midi)) * 100.0
        return (matched, cents)
    }
}

struct LessonItem: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let hole: Int
    let isDraw: Bool
    let bendSteps: Int
    let holdSeconds: Double
    let toleranceCents: Double
    let tip: String
    let vowelCue: String

    static let starterLessons: [LessonItem] = [
        LessonItem(
            id: 1,
            title: "Чистая одиночная нота (4 выдох)",
            subtitle: "База • Постановка дыхания",
            hole: 4, isDraw: false, bendSteps: 0,
            holdSeconds: 2.0, toleranceCents: 25,
            tip: "Погрузи гармошку глубже в рот, не сжимай губы в узкую точку. Дыши спокойно животом, чтобы звук был тёплым и ровным.",
            vowelCue: "Гласная: мягкое «О»"
        ),
        LessonItem(
            id: 2,
            title: "Проклятие 2-го вдоха (-2)",
            subtitle: "База • Глубокий резонанс",
            hole: 2, isDraw: true, bendSteps: 0,
            holdSeconds: 2.0, toleranceCents: 25,
            tip: "Не тяни воздух силой и не задирай язык к нёбу — иначе нота начнёт сипеть или уйдёт вниз. Опусти челюсть, расслабь горло, будто зеваешь.",
            vowelCue: "Ощущение: глубокий вдох «Кх-А-А»"
        ),
        LessonItem(
            id: 3,
            title: "Первый бэнд: 4 вдох (-4')",
            subtitle: "Бэнд на полтона • Самый удобный старт",
            hole: 4, isDraw: true, bendSteps: 1,
            holdSeconds: 1.5, toleranceCents: 18,
            tip: "Сначала возьми чистый 4 вдох. Затем, не меняя силу вдоха, плавно оттяни середину языка назад и чуть вниз — словно пытаешься свистнуть на вдохе.",
            vowelCue: "Переход: «И → Э → О»"
        ),
        LessonItem(
            id: 4,
            title: "Короткий бэнд: 6 вдох (-6')",
            subtitle: "Бэнд на полтона • Точный контроль",
            hole: 6, isDraw: true, bendSteps: 1,
            holdSeconds: 1.5, toleranceCents: 18,
            tip: "На 6-м отверстии движение языка совсем маленькое и ближе к передней части нёба. Не дави воздухом, иначе язычок запрётся.",
            vowelCue: "Переход: «И → Ы»"
        ),
        LessonItem(
            id: 5,
            title: "Глубокий бэнд: 1 вдох (-1')",
            subtitle: "Бэнд на полтона • Низкая октава",
            hole: 1, isDraw: true, bendSteps: 1,
            holdSeconds: 1.5, toleranceCents: 18,
            tip: "Здесь работает задняя часть языка и открытое горло. Опусти челюсть ниже и направь поток воздуха глубже вниз.",
            vowelCue: "Переход: «А → О → У»"
        ),
        LessonItem(
            id: 6,
            title: "Блюзовый бэнд на тон (-2'')",
            subtitle: "Двойной бэнд • Главная нота 2-й позиции",
            hole: 2, isDraw: true, bendSteps: 2,
            holdSeconds: 1.5, toleranceCents: 20,
            tip: "Пройди через первый полутон (-2') и опусти корень языка ещё глубже до упора, сохраняя широкий объём во рту.",
            vowelCue: "Переход: «А → О → глубокое У»"
        )
    ]
}

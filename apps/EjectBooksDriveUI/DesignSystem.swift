//  DesignSystem.swift
//  Eject Books Drive — the Plate system. Generated from docs/tokens.json; see docs/DESIGN.md.
//  Do not add colors, sizes or fonts here without updating those two files.

import SwiftUI

// MARK: - Hex

extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - State

/// The six presentation states. See docs/IMPLEMENTATION.md §1.
enum EjectState: String, CaseIterable {
    case armed, idle, running, succeeded, partial, failed
}

// MARK: - Palette

struct Palette {
    let ground: Color
    let display: Color
    let body: Color
    let mono: Color
    let monoLabel: Color
    let rule: Color
    let strongActionRule: Color
    let dottedLeader: Color
    let windowBorder: Color
    let trackEmpty: Color
    let figureDim: Color
    let disabled: Color
    let lightClose: Color
    let lightInactive: Color

    let working: Color
    let held: Color
    let done: Color
    let fault: Color
    let neutralCapRule: Color

    /// Light ground carries no cap rule — see docs/DESIGN.md §1.
    let showsCapRule: Bool

    static let light = Palette(
        ground: Color(hex: "F1F0EC"),
        display: Color(hex: "16181A"),
        body: Color(hex: "5C605F"),
        mono: Color(hex: "666A61"),
        monoLabel: Color(hex: "676B62"),
        rule: Color(hex: "D6D4CC"),
        strongActionRule: Color(hex: "16181A"),
        dottedLeader: Color(hex: "D2CFC5"),
        windowBorder: Color(hex: "D6D4CC"),
        trackEmpty: Color(hex: "E4DFD2"),
        figureDim: Color(hex: "85837B"),
        disabled: Color(hex: "B4B1A9"),
        lightClose: Color(hex: "C9C6BD"),
        lightInactive: Color(hex: "DEDBD3"),
        working: Color(hex: "96631A"),
        held: Color(hex: "256B86"),
        done: Color(hex: "1E7A50"),
        fault: Color(hex: "8E3B32"),
        neutralCapRule: .clear,
        showsCapRule: false
    )

    static let dark = Palette(
        ground: Color(hex: "121314"),
        display: Color(hex: "F0EFEC"),
        body: Color(hex: "90959A"),
        mono: Color(hex: "8A9095"),
        monoLabel: Color(hex: "7A7F84"),
        rule: Color(hex: "2A2D2F"),
        strongActionRule: Color(hex: "6E7276"),
        dottedLeader: Color(hex: "2E3134"),
        windowBorder: .black,
        trackEmpty: Color(hex: "2A2D2F"),
        figureDim: Color(hex: "6E7276"),
        disabled: Color(hex: "4C5054"),
        lightClose: Color(hex: "3A3D40"),
        lightInactive: Color(hex: "26292B"),
        working: Color(hex: "E8A33D"),
        held: Color(hex: "6FC0E0"),
        done: Color(hex: "7EE0AE"),
        fault: Color(hex: "C4695E"),
        neutralCapRule: Color(hex: "3A3D40"),
        showsCapRule: true
    )

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    /// The single state color. Exactly one is ever on screen.
    func accent(for state: EjectState) -> Color {
        switch state {
        case .armed, .idle:  return working   // the action that starts work
        case .running:       return working
        case .succeeded:     return done
        case .partial:       return held
        case .failed:        return fault
        }
    }

    /// Cap rule color (dark only; armed/idle are neutral).
    func capRule(for state: EjectState) -> Color {
        switch state {
        case .armed, .idle: return neutralCapRule
        default:            return accent(for: state)
        }
    }
}

// MARK: - Type

enum EBDFont {
    static func display(_ scale: CGFloat = 1, success: Bool = false) -> Font {
        .system(size: (success ? 52 : 44) * scale, weight: .bold, design: .default)
    }
    static func body(_ scale: CGFloat = 1) -> Font {
        .system(size: 14 * scale, weight: .regular, design: .default)
    }
    static let eyebrow = Font.system(size: 9.5, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let sectionLabel = Font.system(size: 9, weight: .regular, design: .monospaced)
    static let figure = Font.system(size: 30, weight: .bold, design: .default)
    static let log = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let action = Font.system(size: 10.5, weight: .semibold, design: .default)
    static let facts = Font.system(size: 10.5, weight: .regular, design: .monospaced)
}

enum EBDTracking {
    static let eyebrow: CGFloat = 2.3   // ≈ .24em at 9.5pt
    static let caption: CGFloat = 1.8   // ≈ .18em at 10pt
    static let label: CGFloat = 2.0     // ≈ .22em at 9pt
    static let action: CGFloat = 1.7    // ≈ .16em at 10.5pt
    static let display: CGFloat = -1.5  // ≈ -3.5% at 44pt
    static let displayBig: CGFloat = -2.1
}

enum EBDMetric {
    static let windowWidth: CGFloat = 560
    static let cornerRadius: CGFloat = 8
    static let capRuleHeight: CGFloat = 6
    static let titlebarLight: CGFloat = 34
    static let titlebarDark: CGFloat = 30
    static let contentColumn: CGFloat = 294
    static let columnGap: CGFloat = 30
    static let logColumn: CGFloat = 176
    static let blockGap: CGFloat = 14
    static let figureTrackGap: CGFloat = 9

    // Track — docs/DESIGN.md §4
    static let trackWidth: CGFloat = 294
    static let trackHeight: CGFloat = 3
    static let trackGap: CGFloat = 6
    static let segmentWidth: CGFloat = 69
    static let markWidth: CGFloat = 24
    static let markDrift: CGFloat = 45
    static let markPark: CGFloat = 22
    static let driftDuration: Double = 2.4

    static let logLineLimit = 4
}

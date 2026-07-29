//  EjectWindowView.swift
//  The whole window, every state, driven by one value type. See docs/IMPLEMENTATION.md.
//  Wire EjectController -> EjectPresentation; do not restyle anything below.

import SwiftUI

// MARK: - Presentation model (the only thing the adapter needs to build)

struct LogLine: Identifiable, Equatable {
    let id: UUID
    let time: String      // "10:57:18"
    let message: String   // "tmutil stopbackup"
    var isCurrent: Bool = false

    init(id: UUID = UUID(), time: String, message: String, isCurrent: Bool = false) {
        self.id = id
        self.time = time
        self.message = message
        self.isCurrent = isCurrent
    }
}

struct FactRow: Identifiable, Equatable {
    let id: UUID
    let label: String
    let value: String

    init(id: UUID = UUID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

struct EjectPresentation: Equatable {
    var state: EjectState
    var volumeName: String = "Audiobooks"
    var deviceName: String = "disk6s2"

    /// 1...4 — which track segment is live / was reached. See docs/IMPLEMENTATION.md §1.
    var step: Int = 1
    /// Seconds remaining before auto-start. Only read in .armed.
    var countdown: Int = 3
    /// Elapsed seconds; frozen once a result lands.
    var elapsed: TimeInterval = 0
    /// Blocking process for .partial (nil -> "Another app").
    var holder: String? = nil
    /// Non-EBUSY failure reason; nil uses the standard EBUSY sentence.
    var failureReason: String? = nil

    var facts: [FactRow] = []
    var log: [LogLine] = []

    // MARK: Derived copy — docs/IMPLEMENTATION.md §2

    var eyebrow: String {
        let v = volumeName.uppercased()
        switch state {
        case .armed, .idle: return "\(v) / MOUNTED"
        case .running:      return "\(v) / \(deviceName.uppercased())"
        case .succeeded:    return "\(v) / DETACHED"
        case .partial:      return "\(v) / STILL MOUNTED"
        case .failed:       return "\(v) / UNCHANGED"
        }
    }

    var displayText: String {
        switch state {
        case .armed:     return "Ejecting\nin a moment."
        case .idle:      return "Ready to\neject."
        case .running:   return "Unmounting\nthe library."
        case .succeeded: return "Safe to\nunplug."
        case .partial:   return "One hold.\nYour move."
        case .failed:    return "Still\nmounted."
        }
    }

    var holderName: String { holder ?? "Another app" }

    var supportText: String? {
        switch state {
        case .armed:
            return "Starting on its own. Press Cancel if you opened this by mistake — nothing has changed yet."
        case .idle:
            return nil // the facts list occupies this slot
        case .running:
            return "Time Machine is stopping first. Hold the cable — up to two minutes."
        case .succeeded:
            return "Unmounted cleanly. Zero open handles, Time Machine restored."
        case .partial:
            return "\(holderName) still has the drive open. Quit it and retry — the drive is safe where it is."
        case .failed:
            if let r = failureReason {
                return "The eject failed: \(r). Nothing was changed — leave the cable in."
            }
            return "Three detach attempts returned EBUSY. Nothing was changed — leave the cable in."
        }
    }

    /// Bare integer = about to happen. Colon form = happening or happened. docs/DESIGN.md §3.
    var figureText: String {
        if state == .armed { return String(countdown) }
        let t = Int(elapsed.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var captionText: String {
        switch state {
        case .armed:     return "SECONDS TO CANCEL"
        case .idle:      return "4 STEPS · ABOUT 40S"
        case .running:   return "STEP \(step) / 4"
        case .succeeded: return "4 / 4 COMPLETE"
        case .partial:   return "HELD AT \(step) / 4"
        case .failed:    return "STOPPED AT \(step) / 4"
        }
    }

    var primaryTitle: String {
        switch state {
        case .armed:     return "Start now"
        case .idle:      return "Eject now"
        case .running:   return "Done"
        case .succeeded: return "Done"
        case .partial:   return "Quit \(holderName) & retry"
        case .failed:    return "Retry"
        }
    }

    var secondaryTitle: String {
        switch state {
        case .armed, .idle: return "Cancel"
        default:            return "Open log"
        }
    }

    var primaryEnabled: Bool { state != .running }
    var isRunning: Bool { state == .running }

    /// One sentence for VoiceOver — docs/IMPLEMENTATION.md §7.
    var accessibilitySummary: String {
        [displayText.replacingOccurrences(of: "\n", with: " "), supportText ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Window

struct EjectWindowView: View {
    let model: EjectPresentation
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1

    private var p: Palette { .of(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            if p.showsCapRule {
                Rectangle()
                    .fill(p.capRule(for: model.state))
                    .frame(height: EBDMetric.capRuleHeight)
            }
            titlebar
            HStack(alignment: .top, spacing: EBDMetric.columnGap) {
                contentColumn
                sideColumn
            }
            .padding(.top, 6)
            .padding(.horizontal, 30)
            .padding(.bottom, 28)
        }
        .frame(width: EBDMetric.windowWidth)
        .background(p.ground)
        .overlay(
            RoundedRectangle(cornerRadius: EBDMetric.cornerRadius)
                .stroke(p.windowBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: EBDMetric.cornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilitySummary)
    }

    // MARK: Titlebar

    private var titlebar: some View {
        HStack(spacing: 7) {
            Button {
                NSApp.keyWindow?.close()
            } label: {
                Circle().fill(p.lightClose).frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help("Close")

            Circle().fill(p.lightInactive).frame(width: 10, height: 10)
            Circle().fill(p.lightInactive).frame(width: 10, height: 10)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: p.showsCapRule ? EBDMetric.titlebarDark : EBDMetric.titlebarLight)
    }

    // MARK: Content column

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: EBDMetric.blockGap) {
            Text(model.eyebrow)
                .font(EBDFont.eyebrow)
                .tracking(EBDTracking.eyebrow)
                .foregroundStyle(eyebrowColor)

            Text(model.displayText)
                .font(EBDFont.display(typeScale, success: model.state == .succeeded))
                .tracking(model.state == .succeeded ? EBDTracking.displayBig : EBDTracking.display)
                .lineSpacing(-4)
                .foregroundStyle(p.display)
                .fixedSize(horizontal: false, vertical: true)

            if let support = model.supportText {
                Text(support)
                    .font(EBDFont.body(typeScale))
                    .lineSpacing(2.5)
                    .foregroundStyle(p.body)
                    .frame(maxWidth: EBDMetric.contentColumn, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.state == .idle, !model.facts.isEmpty {
                factsList
            }

            VStack(alignment: .leading, spacing: EBDMetric.figureTrackGap) {
                figureRow
                StepTrack(state: model.state, step: model.step, palette: p, reduceMotion: reduceMotion)
            }
            .padding(.top, 4)
        }
        .frame(width: EBDMetric.contentColumn, alignment: .leading)
    }

    private var eyebrowColor: Color {
        switch model.state {
        case .armed, .idle, .running: return p.mono
        default:                      return p.accent(for: model.state)
        }
    }

    private var factsList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(model.facts) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.label).foregroundStyle(p.mono)
                    Leader(color: p.dottedLeader)
                    Text(row.value).foregroundStyle(p.display.opacity(0.85))
                }
                .font(EBDFont.facts)
            }
        }
        .frame(width: EBDMetric.contentColumn, alignment: .leading)
    }

    private var figureRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(model.figureText)
                .font(EBDFont.figure)
                .monospacedDigit()
                .tracking(-0.9)
                .foregroundStyle(figureColor)
            Text(model.captionText)
                .font(EBDFont.caption)
                .tracking(EBDTracking.caption)
                .foregroundStyle(p.mono)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(figureAccessibility)
    }

    private var figureColor: Color {
        switch model.state {
        case .armed: return p.display
        case .idle:  return p.figureDim
        default:     return p.accent(for: model.state)
        }
    }

    private var figureAccessibility: String {
        switch model.state {
        case .armed: return "Starting in \(model.countdown) seconds"
        case .idle:  return "Four steps, about forty seconds"
        default:     return "\(model.captionText.lowercased()), \(model.figureText) elapsed"
        }
    }

    // MARK: Log + actions

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ACTIVITY")
                .font(EBDFont.sectionLabel)
                .tracking(EBDTracking.label)
                .foregroundStyle(p.monoLabel)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.log.suffix(EBDMetric.logLineLimit)) { line in
                    HStack(spacing: 4) {
                        Text(line.time)
                        Text(line.message).lineLimit(1).truncationMode(.middle)
                        if line.isCurrent && model.isRunning {
                            Caret(color: p.accent(for: model.state), animated: !reduceMotion)
                        }
                    }
                    .font(EBDFont.log)
                    .monospacedDigit()
                    .foregroundStyle(line.isCurrent && model.isRunning
                                     ? p.accent(for: model.state) : p.mono)
                    .frame(height: 20, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Activity log")
            .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 7) {
                ActionButton(title: model.secondaryTitle,
                             hint: model.state == .armed ? "⎋" : nil,
                             color: p.mono,
                             ruleColor: p.rule,
                             enabled: true,
                             hoverColor: p.display,
                             action: onSecondary)
                    .keyboardShortcut(.cancelAction)

                ActionButton(title: model.primaryTitle,
                             hint: model.primaryEnabled ? "⏎" : nil,
                             color: model.primaryEnabled ? p.accent(for: model.state) : p.disabled,
                             ruleColor: model.primaryEnabled ? p.accent(for: model.state) : p.rule,
                             enabled: model.primaryEnabled,
                             hoverColor: p.display,
                             action: onPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: EBDMetric.logColumn, alignment: .leading)
        .padding(.top, 4)
    }
}

// MARK: - Pieces

/// Four segments; the live one holds a drifting mark. docs/DESIGN.md §4.
struct StepTrack: View {
    let state: EjectState
    let step: Int
    let palette: Palette
    let reduceMotion: Bool

    @State private var drifted = false

    private var filledThrough: Int {
        switch state {
        case .armed, .idle: return 0
        case .succeeded:    return 4
        case .running:      return max(0, step - 1)
        case .partial:      return max(0, step - 1)
        case .failed:       return max(0, step - 1)
        }
    }

    private var liveIndex: Int? {
        switch state {
        case .running, .partial: return step
        default:                 return nil
        }
    }

    var body: some View {
        HStack(spacing: EBDMetric.trackGap) {
            ForEach(1...4, id: \.self) { i in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(i <= filledThrough ? palette.accent(for: state) : palette.trackEmpty)
                    if i == liveIndex {
                        Rectangle()
                            .fill(palette.accent(for: state))
                            .frame(width: EBDMetric.markWidth)
                            .offset(x: markOffset)
                    }
                }
                .frame(width: EBDMetric.segmentWidth, height: EBDMetric.trackHeight)
                .clipped()
            }
        }
        .frame(width: EBDMetric.trackWidth, alignment: .leading)
        .onAppear(perform: startDriftIfNeeded)
        .onChange(of: state) { _, _ in startDriftIfNeeded() }
        .accessibilityElement()
        .accessibilityLabel("Step \(min(step, 4)) of 4")
    }

    private var markOffset: CGFloat {
        // Held parks the mark; reduce-motion parks it at the midpoint; running drifts.
        if state == .partial { return EBDMetric.markPark }
        if reduceMotion { return EBDMetric.markDrift / 2 }
        return drifted ? EBDMetric.markDrift : 0
    }

    private func startDriftIfNeeded() {
        guard state == .running, !reduceMotion else {
            drifted = false
            return
        }
        withAnimation(.easeInOut(duration: EBDMetric.driftDuration)
            .repeatForever(autoreverses: true)) {
            drifted = true
        }
    }
}

struct Caret: View {
    let color: Color
    let animated: Bool
    @State private var on = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 5, height: 10)
            .opacity(on ? 1 : 0)
            .onAppear {
                guard animated else { return }
                withAnimation(.linear(duration: 0.55).repeatForever(autoreverses: false)) {
                    on = false
                }
            }
            .accessibilityHidden(true)
    }
}

struct Leader: View {
    let color: Color
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// A label over a 1pt rule — the only button style in the app. No fills, flush left.
struct ActionButton: View {
    let title: String
    let hint: String?
    let color: Color
    let ruleColor: Color
    let enabled: Bool
    let hoverColor: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(ruleColor).frame(height: 1)
                HStack(spacing: 5) {
                    Text(title.uppercased())
                    if let hint { Text(hint) }
                }
                .font(EBDFont.action)
                .tracking(EBDTracking.action)
                .foregroundStyle(enabled ? (hovering ? hoverColor : color) : color)
                .padding(.top, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

// MARK: - Fixtures (also used by --preview; docs/IMPLEMENTATION.md §6)

extension EjectPresentation {
    static func fixture(_ state: EjectState) -> EjectPresentation {
        var m = EjectPresentation(state: state)
        switch state {
        case .armed:
            m.countdown = 3
            m.log = [LogLine(time: "10:56:02", message: "mounted"),
                     LogLine(time: "10:56:02", message: "armed", isCurrent: true)]
        case .idle:
            m.facts = [FactRow(label: "volume", value: "1.82 TB · 61% full"),
                       FactRow(label: "last write", value: "6 min ago"),
                       FactRow(label: "time machine", value: "idle")]
            m.log = [LogLine(time: "10:56:02", message: "mounted"),
                     LogLine(time: "10:56:02", message: "awaiting")]
        case .running:
            m.step = 3; m.elapsed = 8
            m.log = [LogLine(time: "10:57:14", message: "resolve"),
                     LogLine(time: "10:57:15", message: "sparsebundle"),
                     LogLine(time: "10:57:16", message: "flush · 2"),
                     LogLine(time: "10:57:18", message: "stopbackup", isCurrent: true)]
        case .succeeded:
            m.step = 4; m.elapsed = 41
            m.log = [LogLine(time: "10:57:33", message: "tm stopped"),
                     LogLine(time: "10:57:36", message: "detach disk6"),
                     LogLine(time: "10:57:40", message: "eject"),
                     LogLine(time: "10:57:43", message: "removable")]
        case .partial:
            m.step = 3; m.elapsed = 72; m.holder = "Music"
            m.log = [LogLine(time: "10:58:00", message: "tm stopped"),
                     LogLine(time: "10:58:01", message: "detach → busy"),
                     LogLine(time: "10:58:02", message: "pid 4412 Music"),
                     LogLine(time: "10:58:02", message: "waiting on you")]
        case .failed:
            m.step = 2; m.elapsed = 26
            m.log = [LogLine(time: "10:57:36", message: "detach → busy"),
                     LogLine(time: "10:57:38", message: "detach → busy"),
                     LogLine(time: "10:57:41", message: "EBUSY"),
                     LogLine(time: "10:57:41", message: "no changes")]
        }
        return m
    }
}

// SwiftUI #Preview macros require the Xcode Previews plugin — omitted for
// command-line `swiftc` builds. Use --preview=<state> instead.

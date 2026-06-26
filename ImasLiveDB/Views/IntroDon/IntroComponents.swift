import SwiftUI

// MARK: - IDActionButton  (IntroActionButton 相当)

struct IDActionButton: View {
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var isLoading: Bool = false
    var action: () -> Void

    enum Style {
        case primary    // dark card
        case secondary  // subtle
        case danger     // incorrect / red
        case correct    // correct / green
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .scaleEffect(0.85)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.imasScaled( 15, weight: .semibold))
                    }
                    Text(title)
                        .font(ID.font(17, weight: .bold))
                }
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .clipShape(IDCorner())
            .shadow(color: shadowColor, radius: 12, y: 4)
        }
        .idPress()
        .disabled(isLoading)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:   return ID.menuCardDark
        case .secondary: return ID.menuCardSubtle
        case .danger:    return ID.incorrect
        case .correct:   return ID.correct
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:   return ID.menuCardDarkText
        case .secondary: return ID.menuText
        case .danger, .correct: return .white
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary:   return Color.black.opacity(0.18)
        case .secondary: return Color.clear
        case .danger:    return ID.incorrect.opacity(0.35)
        case .correct:   return ID.correct.opacity(0.35)
        }
    }
}

// MARK: - IDEQAnimation  (IntroEQAnimation 相当)

struct IDEQAnimation: View {
    var columns: Int = 16
    var rows: Int = 5
    var dotSize: CGFloat = 10
    var spacing: CGFloat = 3
    var interval: TimeInterval = 0.6
    var activeOpacity: Double = 0.85
    var inactiveOpacity: Double = 0.12
    var color: Color = ID.menuText
    var isAnimating: Bool = true

    private static let baseHeights = [2, 3, 4, 2, 5, 3, 4, 5, 3, 5, 4, 2, 5, 3, 2, 3]

    @State private var heights: [Int] = baseHeights
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { col in
                VStack(spacing: spacing) {
                    ForEach((0..<rows).reversed(), id: \.self) { row in
                        Rectangle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(row < heights[col % heights.count] ? activeOpacity : inactiveOpacity)
                    }
                }
            }
        }
        .frame(height: CGFloat(rows) * (dotSize + spacing) + spacing)
        .animation(.easeInOut(duration: 0.4), value: heights)
        .onAppear { refreshTimer() }
        .onChange(of: isAnimating) { _, _ in refreshTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func refreshTimer() {
        timer?.invalidate()
        timer = nil
        if isAnimating {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                Task { @MainActor in
                    var h = heights
                    for i in 0..<h.count {
                        let variation = Int.random(in: -1...1)
                        h[i] = max(1, min(rows, Self.baseHeights[i % Self.baseHeights.count] + variation))
                    }
                    heights = h
                }
            }
        } else {
            heights = Array(repeating: 1, count: columns)
        }
    }
}

// MARK: - IDProgressBar  (IntroProgressBar 相当)

struct IDProgressBar: View {
    let progress: Double   // 0.0 ~ 1.0
    var color: Color = ID.accentPink
    var bgColor: Color = Color.white.opacity(0.10)
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(bgColor).frame(height: height)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * CGFloat(progress)), height: height)
                    .animation(.linear(duration: 0.15), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - IDModeCard  (IntroModeCard 相当)

struct IDModeCard: View {
    var label: String?
    let title: String
    var description: String?
    var style: Style = .white
    var action: () -> Void

    enum Style {
        case dark, white, subtle

        var bg: Color {
            switch self {
            case .dark:   return ID.menuCardDark
            case .white:  return ID.menuCardWhite
            case .subtle: return ID.menuCardSubtle
            }
        }

        var textColor: Color {
            switch self {
            case .dark:             return ID.menuCardDarkText
            case .white, .subtle:   return ID.menuText
            }
        }

        var labelColor: Color {
            switch self {
            case .dark:             return ID.menuCardDarkText.opacity(0.35)
            case .white, .subtle:   return ID.menuTextSecondary
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let label {
                        Text(label)
                            .font(ID.font(11, weight: .bold))
                            .tracking(2)
                            .foregroundColor(style.labelColor)
                    }
                    Text(title)
                        .font(ID.font(22, weight: .black))
                        .tracking(-0.5)
                        .foregroundColor(style.textColor)
                    if let description {
                        Text(description)
                            .font(.imasScaled( 12))
                            .foregroundColor(style.labelColor)
                    }
                }
                Spacer()
                Text("\u{203A}")
                    .font(.imasScaled( 28))
                    .foregroundColor(style.labelColor)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .background(style.bg)
            .clipShape(IDCorner())
        }
        .idPress()
    }
}

// MARK: - IDAnswerReveal  (IntroAnswerReveal 相当)

struct IDAnswerReveal: View {
    let title: String
    let choices: [String]
    let correctTitle: String
    let selectedTitle: String?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices, id: \.self) { choice in
                revealRow(choice)
            }
        }
    }

    private func revealRow(_ choice: String) -> some View {
        let isCorrect   = choice == correctTitle
        let wasSelected = choice == selectedTitle

        let tint: Color
        let bg: Color
        let icon: String
        if isCorrect {
            tint = ID.correct
            bg   = ID.correct.opacity(0.15)
            icon = "checkmark.circle.fill"
        } else if wasSelected {
            tint = ID.incorrect
            bg   = ID.incorrect.opacity(0.12)
            icon = "xmark.circle.fill"
        } else {
            tint = ID.t2
            bg   = ID.surfaceDarkSubtle
            icon = "circle"
        }

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.imasScaled( 17, weight: .semibold))
                .foregroundColor(tint)

            Text(choice)
                .font(.imasScaled( 14, weight: isCorrect ? .semibold : .regular))
                .foregroundColor(tint)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(bg)
        .clipShape(IDCorner(radius: 10))
    }
}

// MARK: - IDSectionLabel (SettingsView の sectionHeader 相当)

struct IDSectionLabel: View {
    let text: String
    var hint: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(ID.font(11, weight: .bold))
                .tracking(2)
                .foregroundColor(ID.menuTextMuted)
            if let hint {
                Text(hint)
                    .font(.imasScaled(11))
                    .minimumScaleFactor(0.8)
                    .foregroundColor(ID.menuTextMuted.opacity(0.7))
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}

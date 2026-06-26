import SwiftUI
import MusicKit

struct IntroGameSetupView: View {
    @Environment(AppDatabase.self) private var database

    @State private var session = IntroGameSession()
    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []
    @State private var questionCount: Int = 10
    @State private var introDuration: TimeInterval = 5.0
    @State private var isLoading = false
    @State private var navigateToGame = false
    @State private var errorMessage: String? = nil
    @State private var authStatus: MusicAuthorization.Status = MusicKitService.shared.authorizationStatus

    private let questionCounts = [5, 10, 20]
    private let durations: [(label: String, sub: String, value: TimeInterval)] = [
        ("0.2秒", "超イントロ", 0.2),
        ("2秒", "再生", 2.0),
        ("5秒", "再生", 5.0),
        ("10秒", "再生", 10.0),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                IDSectionLabel(text: "ブランド")
                    .padding(.horizontal, 20)
                Spacer().frame(height: 12)
                brandSection
                    .padding(.horizontal, 20)

                Spacer().frame(height: 24)

                IDSectionLabel(text: "問題数")
                    .padding(.horizontal, 20)
                Spacer().frame(height: 12)
                countSection
                    .padding(.horizontal, 20)

                Spacer().frame(height: 24)

                IDSectionLabel(text: "難易度", hint: "イントロ再生時間")
                    .padding(.horizontal, 20)
                Spacer().frame(height: 12)
                durationSection
                    .padding(.horizontal, 20)

                if authStatus != .authorized {
                    Spacer().frame(height: 20)
                    authWarningCard
                        .padding(.horizontal, 20)
                }

                if let err = errorMessage {
                    Spacer().frame(height: 16)
                    errorCard(err)
                        .padding(.horizontal, 20)
                }

                Spacer().frame(height: 32)

                IDActionButton(
                    title: isLoading ? "問題を生成中..." : "スタート",
                    icon: isLoading ? nil : "play.fill",
                    style: .primary,
                    isLoading: isLoading
                ) {
                    AppAnalytics.tap("intro_game_setup.start")
                    Task { await startGame() }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 32)
            }
            .padding(.top, 16)
        }
        .background(ID.menuBg.ignoresSafeArea())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToGame) {
            IntroGameView(session: session)
        }
        .task {
            brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
        }
        .trackScreen("intro_game_setup")
    }

    // MARK: - Brand Section

    private var brandSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedBrandIds.removeAll()
                }
            } label: {
                HStack {
                    Text("全ブランド")
                        .font(ID.font(14, weight: .semibold))
                        .foregroundColor(ID.menuText)
                    Spacer()
                    checkIcon(selected: selectedBrandIds.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .idPress()

            brandDivider

            ForEach(Array(brands.enumerated()), id: \.element.id) { index, brand in
                let selected = selectedBrandIds.contains(brand.id)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if selected {
                            selectedBrandIds.remove(brand.id)
                        } else {
                            selectedBrandIds.insert(brand.id)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if let hex = brand.color {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 8, height: 8)
                        }
                        Text(brand.shortName)
                            .font(ID.font(14, weight: .semibold))
                            .foregroundColor(ID.menuText)
                        Spacer()
                        checkIcon(selected: selected)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .idPress()

                if index < brands.count - 1 {
                    brandDivider
                }
            }
        }
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner(radius: 16))
    }

    private func checkIcon(selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(selected ? ID.correct : ID.menuTextMuted)
            .font(.imasScaled( 18))
    }

    private var brandDivider: some View {
        Rectangle()
            .fill(ID.menuDivider)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Count / Duration Sections

    private var countSection: some View {
        HStack(spacing: 8) {
            ForEach(questionCounts, id: \.self) { n in
                IDSegmentButton(
                    primary: "\(n)",
                    secondary: "問",
                    selected: questionCount == n
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { questionCount = n }
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(durations, id: \.value) { d in
                    IDSegmentButton(
                        primary: d.label,
                        secondary: d.sub,
                        selected: abs(introDuration - d.value) < 0.001
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { introDuration = d.value }
                    }
                }
            }

            // 細かく秒数を決めるスライダー (0.2〜10秒)。超イントロ(1秒未満)も自由に。
            VStack(spacing: 6) {
                HStack {
                    Text(introDuration < 1.0 ? "超イントロ" : "再生時間")
                        .font(ID.font(12, weight: .semibold))
                        .foregroundColor(introDuration < 1.0 ? ID.accentGold : ID.menuTextSecondary)
                    Spacer()
                    Text(String(format: "%.1f秒", introDuration))
                        .font(ID.font(14, weight: .bold))
                        .foregroundColor(ID.menuText)
                        .monospacedDigit()
                }
                Slider(value: $introDuration, in: 0.2...10.0, step: 0.1)
                    .tint(ID.accentGold)
            }
        }
    }

    // MARK: - Warnings / Error

    private var authWarningCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(ID.accentGold)
                Text("Apple Music が未認証です")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.menuText)
                Spacer()
            }
            IDActionButton(title: "Apple Music を許可する", style: .secondary) {
                AppAnalytics.tap("intro_game_setup.music_auth")
                Task {
                    await MusicKitService.shared.requestAuthorization()
                    authStatus = MusicKitService.shared.authorizationStatus
                }
            }
        }
        .padding(14)
        .background(ID.accentGold.opacity(0.08))
        .clipShape(IDCorner(radius: 14))
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(ID.incorrect)
            Text(msg)
                .font(.imasScaled( 13))
                .foregroundColor(ID.menuText)
            Spacer()
        }
        .padding(14)
        .background(ID.incorrect.opacity(0.08))
        .clipShape(IDCorner(radius: 14))
    }

    // MARK: - Start

    private func startGame() async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true

        if MusicKitService.shared.authorizationStatus == .notDetermined {
            await MusicKitService.shared.requestAuthorization()
            authStatus = MusicKitService.shared.authorizationStatus
        }

        session.settings = IntroGameSettings(
            questionCount: questionCount,
            introDuration: introDuration,
            selectedBrandIds: selectedBrandIds.isEmpty ? nil : selectedBrandIds
        )

        do {
            try await session.generateQuestions(database: database)
            if session.questions.isEmpty {
                errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
            } else {
                navigateToGame = true
            }
        } catch {
            errorMessage = "エラー: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - IDSegmentButton

private struct IDSegmentButton: View {
    let primary: String
    let secondary: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(primary)
                    .font(ID.font(22, weight: .black))
                Text(secondary)
                    .font(ID.font(11, weight: .bold))
            }
            .foregroundColor(selected ? ID.menuCardDarkText : ID.menuTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selected ? ID.menuCardDark : ID.menuCardSubtle)
            .clipShape(IDCorner(radius: 16))
        }
        .idPress()
    }
}

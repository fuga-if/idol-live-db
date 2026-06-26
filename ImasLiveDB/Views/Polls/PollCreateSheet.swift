import SwiftUI

/// お題作成シート。デザインシステム準拠 (ImasSectionHeader / ImasListContainer /
/// ImasSegmented + 対象カード)。
struct PollCreateSheet: View {
    let onCreate: (Poll) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var targetType: PollTargetType = .song
    @State private var dayIndex = 1   // 0:7 / 1:14 / 2:30
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let dayOptions = [7, 14, 30]
    private var days: Int { dayOptions[dayIndex] }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool { !trimmedTitle.isEmpty && !isSubmitting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    Text("お題を作って、みんなに推しを投票してもらおう。期間中は誰でも3票まで投票できます。")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    fieldSection(header: "タイトル", counter: "\(title.count)/80") {
                        TextField("例: 夏に聴きたい曲は？", text: $title, axis: .vertical)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .lineLimit(1...3)
                            .onChange(of: title) { _, new in
                                if new.count > 80 { title = String(new.prefix(80)) }
                            }
                    }

                    fieldSection(header: "説明（任意）", counter: "\(description.count)/280") {
                        TextField("補足やルールがあれば（任意）", text: $description, axis: .vertical)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .lineLimit(2...5)
                            .onChange(of: description) { _, new in
                                if new.count > 280 { description = String(new.prefix(280)) }
                            }
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "投票対象", tight: true)
                        HStack(spacing: DS.sp3) {
                            targetCard(.song, icon: "music.note", label: "曲")
                            targetCard(.idol, icon: "person.fill", label: "アイドル")
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "募集期間", tight: true)
                        ImasSegmented(labels: dayOptions.map { "\($0)日間" }, selection: $dayIndex)
                    }

                    if let msg = errorMessage {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp7)
            }
            .background(DS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("お題を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("poll_create")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("作成") {
                        AppAnalytics.tap("poll_create.submit")
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func fieldSection<Content: View>(
        header: String, counter: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: header, tight: true)
            ImasListContainer {
                content()
                    .padding(.horizontal, DS.sp4)
                    .padding(.vertical, DS.sp3)
            }
            Text(counter)
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func targetCard(_ type: PollTargetType, icon: String, label: String) -> some View {
        let on = targetType == type
        return Button { targetType = type } label: {
            VStack(spacing: DS.sp2) {
                Image(systemName: icon).font(.imasScaled( 22, weight: .semibold))
                Text(label).font(.imasSubhead.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.sp4)
            .foregroundStyle(on ? Color.accentColor : DS.ink2)
            .background(
                on ? Color.accentColor.opacity(0.12) : DS.surface,
                in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMD, style: .continuous)
                    .strokeBorder(on ? Color.accentColor : DS.sep, lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        do {
            let poll = try await AppContainer.shared.communityVoting.createPoll(
                title: trimmedTitle,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                targetType: targetType,
                days: days
            )
            onCreate(poll)
            dismiss()
        } catch {
            // APIClientError の説明 (認証エラー/上限到達等) をそのまま見せる
            errorMessage = (error as? APIClientError)?.errorDescription
                ?? "作成に失敗しました。時間をおいて再試行してください。"
        }
    }
}

import SwiftUI

/// キャラ同士の SNS 風タイムライン (AI・非公式)。引っ張って更新で続きを生成する。
/// 見た目はこのアプリのカードの作法で組む (特定の SNS の見た目には寄せない)。
struct CharacterTimelineView: View {
    private var timeline: CharacterTimelineStore { .shared }
    private var cache: CharacterIdolCache { .shared }
    @AppStorage("chatgpt_plan.model") private var selectedModel = ""
    @State private var replyTarget: TimelinePost?

    var body: some View {
        ImasPage {
            CharacterDisclaimerBadge()
            if timeline.isGenerating {
                ImasChatToolChip(label: "タイムラインを更新しています…")
            }
            if let error = timeline.errorMessage {
                Text(error).imasText(.note, color: DS.warning).multilineTextAlignment(.center)
            }
            if timeline.posts.isEmpty, !timeline.isGenerating {
                emptyState
            }
            ForEach(timeline.posts) { post in
                TimelinePostCard(
                    post: post,
                    idols: cache.idols,
                    isReplying: timeline.replyingPostID == post.id,
                    onReply: { replyTarget = post }
                )
            }
        }
        .refreshable { await timeline.generate(model: selectedModel) }
        .task(id: timeline.posts.count) { await cache.load(idolIDs) }
        .sheet(item: $replyTarget) { post in
            TimelineReplySheet(post: post, authorName: cache.idols[post.idolID]?.name ?? "") { text in
                Task {
                    await timeline.reply(
                        to: post.id, text: text,
                        authorName: cache.idols[post.idolID]?.name ?? "", model: selectedModel
                    )
                }
            }
        }
        .sheet(isPresented: Binding(get: { timeline.usageLimitHit }, set: { timeline.usageLimitHit = $0 })) {
            AssistantUsageLimitSheet()
        }
    }

    private var idolIDs: [String] {
        timeline.posts.flatMap { [$0.idolID] + $0.replies.compactMap(\.idolID) }
    }

    private var emptyState: some View {
        ImasEmptyState(
            systemImage: "bubble.left.and.text.bubble.right",
            title: "アイドルたちのタイムライン",
            message: "近日のライブや最近の公演・新曲を話題に、アイドルどうしのやりとりを生成します。担当がいればその子が多めに登場します。",
            actionTitle: "タイムラインを見る",
            action: selectedModel.isEmpty ? nil : { Task { await timeline.generate(model: selectedModel) } }
        )
    }
}

/// 投稿 1 件とリプライのツリー。
private struct TimelinePostCard: View {
    let post: TimelinePost
    let idols: [String: Idol]
    let isReplying: Bool
    let onReply: () -> Void

    var body: some View {
        ImasCard {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                entry(idolID: post.idolID, text: post.text, date: post.createdAt)
                if !post.replies.isEmpty || isReplying {
                    VStack(alignment: .leading, spacing: DS.Space.gap) {
                        ForEach(post.replies) { reply in
                            if let idolID = reply.idolID {
                                entry(idolID: idolID, text: reply.text, date: reply.createdAt)
                            } else {
                                ImasChatBubble(role: .user, content: .text(reply.text))
                            }
                        }
                        if isReplying {
                            ImasChatToolChip(label: "\(idols[post.idolID]?.name ?? "")が返信を書いています…")
                        }
                    }
                    .padding(.leading, DS.Space.section)
                }
                HStack {
                    Spacer()
                    Button(action: onReply) {
                        Label("返信", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.imas(.plain, size: .small))
                    .disabled(isReplying)
                }
            }
        }
    }

    private func entry(idolID: String, text: String, date: Date) -> some View {
        ImasChatBubble(
            role: .assistant,
            content: .text(text),
            partnerName: "\(idols[idolID]?.name ?? "") · \(date.formatted(.relative(presentation: .numeric)))",
            seed: idols[idolID]?.color
        ) {
            if let idol = idols[idolID] {
                IdolAvatarView(idol: idol, size: 36, reservesPickRing: false)
            } else {
                ImasIconTile(systemImage: "person.fill", size: .s32, tone: .neutral)
            }
        }
    }
}

/// 投稿へのリプライを書くシート。
private struct TimelineReplySheet: View {
    let post: TimelinePost
    let authorName: String
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormField(label: "投稿", imprint: "POST") {
                        Text(post.text).imasText(.body, color: DS.ink2)
                    }
                    ImasFormTextArea(label: "返信", imprint: "REPLY", text: $text, prompt: "\(authorName)に返信",
                                      autofocus: true)
                }
                AssistantPlanFooter()
            }
            .navigationTitle("返信")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.submit(
                canSubmit: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: { dismiss() },
                onSubmit: {
                    onSend(text)
                    dismiss()
                }
            ))
        }
        .presentationDetents([.medium])
    }
}

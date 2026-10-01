import SwiftUI

/// キャラ同士の SNS 風タイムライン (AI・非公式)。引っ張って更新で続きを生成する。
/// 見た目はこのアプリのカードの作法で組む (特定の SNS の見た目には寄せない)。
struct CharacterTimelineView: View {
    private var timeline: CharacterTimelineStore { .shared }
    private var cache: CharacterIdolCache { .shared }
    @AppStorage("chatgpt_plan.model") private var selectedModel = ""
    @State private var replyTarget: TimelinePost?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.sp4) {
                CharacterDisclaimerBadge()
                if timeline.isGenerating {
                    HStack(spacing: DS.sp3) {
                        ProgressView().controlSize(.small)
                        Text("タイムラインを更新しています…").font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                    .padding(.vertical, DS.sp2)
                }
                if let error = timeline.errorMessage {
                    Text(error).font(.imasCaption).foregroundStyle(DS.warning).multilineTextAlignment(.center)
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
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp4)
        }
        .background(DS.bg.ignoresSafeArea())
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
        VStack(spacing: DS.sp4) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(DS.ink3)
            Text("アイドルたちのタイムライン")
                .font(.imasHeadline)
            Text("近日のライブや最近の公演・新曲を話題に、アイドルどうしのやりとりを生成します。担当がいればその子が多めに登場します。")
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
                .multilineTextAlignment(.center)
            Button("タイムラインを見る") {
                Task { await timeline.generate(model: selectedModel) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedModel.isEmpty)
        }
        .padding(.vertical, DS.sp8)
        .padding(.horizontal, DS.sp5)
    }
}

/// 投稿 1 件とリプライのツリー。
private struct TimelinePostCard: View {
    let post: TimelinePost
    let idols: [String: Idol]
    let isReplying: Bool
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            entry(idolID: post.idolID, text: post.text, date: post.createdAt, avatarSize: 40, textFont: .imasBody)
            if !post.replies.isEmpty || isReplying {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    ForEach(post.replies) { reply in
                        if let idolID = reply.idolID {
                            entry(idolID: idolID, text: reply.text, date: reply.createdAt, avatarSize: 28, textFont: .imasSubhead)
                        } else {
                            producerEntry(reply)
                        }
                    }
                    if isReplying {
                        HStack(spacing: DS.sp3) {
                            ProgressView().controlSize(.mini)
                            Text("\(idols[post.idolID]?.name ?? "")が返信を書いています…")
                                .font(.imasCaption).foregroundStyle(DS.ink2)
                        }
                    }
                }
                .padding(.leading, DS.sp5)
                .overlay(alignment: .leading) {
                    Rectangle().fill(accent.opacity(0.35)).frame(width: 2)
                }
                .padding(.leading, 19)
            }
            HStack {
                Spacer()
                Button(action: onReply) {
                    Label("返信", systemImage: "arrowshape.turn.up.left")
                        .font(.imasCaption)
                }
                .buttonStyle(.borderless)
                .disabled(isReplying)
            }
        }
        .padding(DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            // アイドルカラーの差し色 (カードの上辺)。
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(accent)
                .frame(height: 3)
        }
    }

    private var accent: Color { Color(hexString: idols[post.idolID]?.color, default: DS.ink3) }

    private func entry(idolID: String, text: String, date: Date, avatarSize: CGFloat, textFont: Font) -> some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            if let idol = idols[idolID] {
                IdolAvatarView(idol: idol, size: avatarSize, reservesPickRing: false)
            } else {
                Circle().fill(DS.fill).frame(width: avatarSize, height: avatarSize)
            }
            VStack(alignment: .leading, spacing: DS.sp1) {
                HStack(spacing: DS.sp2) {
                    Text(idols[idolID]?.name ?? "")
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(DS.ink)
                    Text(date.formatted(.relative(presentation: .numeric)))
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink3)
                }
                Text(text)
                    .font(textFont)
                    .foregroundStyle(DS.ink)
                    .textSelection(.enabled)
            }
        }
    }

    private func producerEntry(_ reply: TimelinePost.Reply) -> some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("あなた")
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                Text(reply.text).font(.imasSubhead).foregroundStyle(DS.ink)
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
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.sp4) {
                Text(post.text)
                    .font(.imasCallout)
                    .foregroundStyle(DS.ink2)
                    .padding(DS.sp4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                TextField("\(authorName)に返信", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
                    .padding(DS.sp4)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                AssistantPlanFooter()
                Spacer()
            }
            .padding(DS.sp5)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("返信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") {
                        onSend(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

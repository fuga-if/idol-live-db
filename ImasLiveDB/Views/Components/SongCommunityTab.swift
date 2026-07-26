import SwiftUI
import NukeUI

/// コミュニティタブが親に投げる要求。
///
/// タブ側は「ユーザーが何をしたがっているか」だけを伝え、どのシートをどう出すかは
/// 親 (`SongSheetContent`) が決める。タブが親の `@State` を直接書かないので、
/// タブ単体で完結して読める。
enum SongCommunityIntent {
    case addTag
    case createCall
    case editCall(SongCall)
    case createVideo
    case editVideo(SongVideo)
    case votePenlight
    /// タグを外す (自分が付けたタグのみ)。
    case removeTag(id: String)
}

/// 楽曲詳細のコミュニティタブ。タグ / 類似曲 / コーレス / 参考動画 / ペンライト投票。
///
/// 表示データは `DetailSheetViewModel` を読むだけ (書かない)。
/// 画面遷移と、シート表示を伴う操作は閉包で親へ返す。
struct SongCommunityTab: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    let song: Song
    /// 配色シード (ソロ曲は担当色、それ以外はブランド色)。
    let seed: String?
    let vm: DetailSheetViewModel
    let navigate: (DetailDestination) -> Void
    let onIntent: (SongCommunityIntent) -> Void

    private var permission: EditPermissionRules { EditPermission.rules }

    var body: some View {
        VStack(spacing: DS.sp5) {
            PollAchievementBadges(entityId: song.id)
            InlineLoginPrompt(message: "タグ・コーレス・投票にはログインが必要です", seed: seed)
            tags
            if !vm.similarTagSongs.isEmpty { similarByTags }
            calls
            videos
            penlight
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    // MARK: - タグ

    @ViewBuilder
    private var tags: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            header(title: "タグ", actionLabel: "タグ", systemImage: "plus") {
                AppAnalytics.tap("song_detail.tag_action")
                onIntent(.addTag)
            }
            if let tagData = vm.songTagData, !tagData.tags.isEmpty {
                let myTagIds = Set(tagData.myTagIds)
                FlowLayout(spacing: DS.sp3) {
                    ForEach(tagData.tags) { tag in
                        tagChip(tag, isMine: myTagIds.contains(tag.id))
                    }
                }
            } else {
                ImasEmptyState(systemImage: "tag", title: "タグはまだありません",
                               message: "この曲を一言で表すタグを付けてみませんか？",
                               actionTitle: permission.showEditAffordance ? "タグを追加" : nil,
                               action: permission.showEditAffordance ? { onIntent(.addTag) } : nil,
                               seed: seed)
            }
        }
    }

    private func tagChip(_ tag: SongTagEntry, isMine: Bool) -> some View {
        Button { navigate(.tagDetail(tag)) } label: {
            // 何人がこのタグを付けたか (票数) を常に表示。
            ImasChip(text: "\(tag.name) \(tag.voteCount)",
                     style: isMine ? .selected : .themed,
                     seed: seed)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isMine {
                Button(role: .destructive) {
                    onIntent(.removeTag(id: tag.id))
                } label: { Label("タグを外す", systemImage: "tag.slash") }
            }
            Button { navigate(.tagDetail(tag)) } label: { Label("タグ詳細を見る", systemImage: "tag") }
        }
    }

    /// この曲が好きな人にはこれもおすすめ — タグが似ている楽曲 (サーバ算出)。
    private var similarByTags: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("この曲が好きな人にはこれも")
                    .font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
                Text("つけられたタグが似ている楽曲")
                    .font(.imasCaption).foregroundStyle(DS.ink2)
            }
            ImasListContainer {
                ForEach(Array(vm.similarTagSongs.enumerated()), id: \.element.id) { idx, s in
                    if idx > 0 { ImasRowDivider(inset: DS.sp5 + 44) }
                    Button { navigate(.song(s)) } label: {
                        RelatedSongRow(song: s, seed: seed,
                                       badge: vm.similarSharedTags[s.id].map { "タグ\($0)個一致" })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - コーレス

    @ViewBuilder
    private var calls: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            header(title: "コーレス", actionLabel: "コール", systemImage: "megaphone") {
                AppAnalytics.tap("song_detail.call_action")
                onIntent(.createCall)
            }
            if vm.songCalls.isEmpty {
                ImasEmptyState(systemImage: "megaphone", title: "コーレスはまだありません",
                               message: "サビ前のコールなど、現地の盛り上げ方を共有しませんか？",
                               actionTitle: permission.showEditAffordance ? "コーレスを投稿" : nil,
                               action: permission.showEditAffordance ? { onIntent(.createCall) } : nil,
                               seed: seed)
            } else {
                ImasListContainer {
                    ForEach(Array(vm.songCalls.enumerated()), id: \.element.id) { idx, call in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5) }
                        callRow(call)
                    }
                }
            }
        }
    }

    private func callRow(_ call: SongCall) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // コーレスは長文で「サビ前のここだけ引用したい」需要があるので、
            // 全文一括ではなくネイティブの選択バーで部分コピーできるようにする。
            Text(call.callText)
                .font(.imasSubhead).foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
                .imasSelectableText()
            HStack(spacing: DS.sp3) {
                if let link = URL.safeHTTP(string: call.sourceUrl) {
                    Link(destination: link) {
                        Label("出典", systemImage: "link").font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                }
                if let author = call.authorDisplayName {
                    Text("投稿者: \(author)").font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 4)
                if permission.showEditAffordance {
                    Button { onIntent(.editCall(call)) } label: {
                        Image(systemName: "pencil").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
    }

    // MARK: - 参考動画

    @ViewBuilder
    private var videos: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            header(title: "参考動画", actionLabel: "動画", systemImage: "play.fill") {
                AppAnalytics.tap("song_detail.video_action")
                onIntent(.createVideo)
            }
            if vm.songVideos.isEmpty {
                ImasEmptyState(systemImage: "play.rectangle", title: "参考動画はまだありません",
                               message: "最初の1本を投稿しませんか？",
                               actionTitle: permission.showEditAffordance ? "動画を投稿" : nil,
                               action: permission.showEditAffordance ? { onIntent(.createVideo) } : nil,
                               seed: seed)
            } else {
                ImasListContainer {
                    ForEach(Array(vm.songVideos.enumerated()), id: \.element.id) { idx, video in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5) }
                        videoRow(video)
                    }
                }
            }
        }
    }

    private func videoRow(_ video: SongVideo) -> some View {
        let videoID = YouTube.videoID(from: video.youtubeUrl)
        return VStack(alignment: .leading, spacing: DS.sp3) {
            if let videoID, let url = URL.safeHTTP(string: video.youtubeUrl) {
                // 公式 MV は埋め込み無効が多くアプリ内再生不可 (YouTube仕様) のため、
                // サムネタップで YouTube アプリ/Safari を開く。
                Button { openURL(url) } label: {
                    videoThumbnail(videoID: videoID)
                }
                .buttonStyle(.plain)
            }
            if let title = video.videoTitle {
                Text(title).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
            }
            if videoID == nil, let url = URL.safeHTTP(string: video.youtubeUrl) {
                // YouTube 以外 (または ID 解析不可) は従来どおり外部リンク。
                Link(destination: url) {
                    Label(video.youtubeUrl, systemImage: "play.rectangle.fill")
                        .font(.imasCaption).foregroundStyle(DS.danger)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if let note = video.note, !note.isEmpty {
                Text(note).font(.imasCaption).foregroundStyle(DS.ink2)
                    .imasSelectableText()
            }
            HStack(spacing: DS.sp3) {
                if let author = video.authorDisplayName {
                    Text("投稿者: \(author)").font(.imasCaption).foregroundStyle(DS.ink3)
                }
                Spacer(minLength: 4)
                if permission.showEditAffordance {
                    Button { onIntent(.editVideo(video)) } label: {
                        Image(systemName: "pencil").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 11)
    }

    private func videoThumbnail(videoID: String) -> some View {
        ZStack {
            LazyImage(url: YouTube.thumbnailURL(for: videoID)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    // maxresdefault が無い動画は mqdefault にフォールバック。
                    LazyImage(url: YouTube.fallbackThumbnailURL(for: videoID)) { fb in
                        if let image = fb.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(DS.surface2)
                        }
                    }
                } else {
                    Rectangle().fill(DS.surface2)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
            Image(systemName: "play.circle.fill")
                .font(.imasScaled( 46))
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.35), radius: 5)
        }
        .contentShape(Rectangle())
    }

    // MARK: - ペンライト投票

    @ViewBuilder
    private var penlight: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            header(title: "ペンライト投票", actionLabel: "投票する", systemImage: "sparkles") {
                AppAnalytics.tap("song_detail.penlight_action")
                onIntent(.votePenlight)
            }
            if let votes = vm.penlightVotes, !votes.topColorSets.isEmpty {
                ImasListContainer {
                    ForEach(Array(votes.topColorSets.enumerated()), id: \.element.id) { idx, set in
                        if idx > 0 { ImasRowDivider(inset: DS.sp5) }
                        penlightRow(set, myKey: votes.myColorSet?.key, total: max(votes.totalVotes, 1))
                    }
                }
                Text("この曲のペンライト色 ・ \(votes.totalVotes)票")
                    .font(.imasCaption).foregroundStyle(DS.ink2)
                    .padding(.leading, DS.sp1)
            } else {
                ImasEmptyState(systemImage: "lightspectrum.horizontal", title: "まだ投票がありません",
                               message: "あなたが思うこの曲のペンライト色を投票しませんか？",
                               actionTitle: permission.showEditAffordance ? "ペンライト色を投票" : nil,
                               action: permission.showEditAffordance ? { onIntent(.votePenlight) } : nil,
                               seed: seed)
            }
        }
    }

    private func penlightRow(_ set: PenlightColorSet, myKey: String?, total: Int) -> some View {
        let isMine = myKey == set.key
        return VStack(spacing: 7) {
            HStack(spacing: DS.sp3) {
                PenlightColorBar(colors: set.colors.map(\.rawValue), height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
                    .frame(maxWidth: 120)
                if isMine {
                    Text("自分の投票").font(.imasCaption.weight(.semibold)).foregroundStyle(DS.pick)
                }
                Spacer(minLength: 4)
                Text("\(set.count)票").font(.imasDisplay(13, weight: .semibold)).foregroundStyle(DS.ink2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(DS.pick.opacity(0.7))
                        .frame(width: max(4, geo.size.width * CGFloat(set.count) / CGFloat(total)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, DS.sp5).padding(.vertical, 10)
    }

    /// セクション見出し + 文脈投稿導線 (＋タグ / ＋コール / ▶動画 / ✦投票)。
    @ViewBuilder
    private func header(title: String, actionLabel: String, systemImage: String, action: @escaping () -> Void) -> some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.imasTitle3.weight(.bold)).foregroundStyle(DS.ink)
            Spacer(minLength: 12)
            if permission.showEditAffordance {
                Button(action: action) {
                    HStack(spacing: DS.sp2) {
                        Image(systemName: systemImage).font(.imasScaled( 13, weight: .semibold))
                        Text(actionLabel).font(.imasScaled( 14, weight: .semibold))
                    }
                    .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

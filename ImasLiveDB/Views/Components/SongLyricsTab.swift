import SwiftUI

/// 楽曲詳細の歌詞タブ = **そのままコールガイド**。
///
/// コール表を別画面に切らないのは、コールが歌詞の一部に掛かるものだから。
/// 画面を分けると読み手が 2 つの本文を目で往復することになる。だからこのタブは
/// コールが無ければただの歌詞、あれば歌詞の下にコールが並ぶ、の 1 枚で通す。
/// 編集も同じ画面 (編集モードに切り替える) で行う。
///
/// 歌詞は曲詳細の束ね取得 (`GET /songs/{id}/detail`) に同梱されて届くので、
/// このタブは `DetailSheetViewModel` を読むだけ。タブを開いても**追加のリクエストは飛ばない**
/// (旧実装は ⋯ メニュー →「歌詞を見る」で push した先で個別に取りに行っていた)。
///
/// ⚠️ JASRAC 許諾の条件により、歌詞は**保存も一括取得もさせない**:
/// - 取得はメモリのみ保持の経路 (`SongDetailReading` / ephemeral セッション)。ディスクに書かない。
/// - 本文にテキスト選択 (`.imasSelectableText()` / `textSelection(.enabled)`) や
///   `imasCopyable` を**付けない**。コピー導線を作ると一括取り出しの入口になる。
///   編集モードの範囲選択もシステムのテキスト選択ではなく独自実装
///   (`CallGuideSelectableLine`) で、コピーメニューは一切生えない。
/// - 共有 / 画像化 (`ShareCardScaffold`) にも繋がない。
/// - コールの保存で歌詞本文を送らない (`CallGuidePayload`)。
struct SongLyricsTab: View {
    typealias Playback = LyricsPlayback

    @Environment(\.colorScheme) private var scheme

    let song: Song
    /// 配色シード (ソロ曲は担当色、それ以外はブランド色)。
    let seed: String?
    let vm: DetailSheetViewModel
    /// 色を敷いて示す行 (歌詞クイズの出題箇所)。スクロールは親 (`SongSheetContent`) が行 id で行う。
    var focusLineIds: Set<String> = []
    var playback = Playback()
    /// 通信失敗時の再試行 (束ね取得のやり直し)。
    let reload: () -> Void

    #if DEBUG
    /// スクリーンショット検証用に、歌詞が届いた時点で編集モードに入る (DEBUG ビルドのみ)。
    /// `CallGuidePreviewHarness` からしか渡らない。Release ビルドにはこの口自体が存在しない。
    var debugStartsEditing = false
    /// 同じく、歌詞が届いた時点でタイミング編集を開く (DEBUG のみ)。
    var debugStartsRecording = false
    /// 同じく、歌詞が届いた時点で歌詞プレイヤーを開く (DEBUG のみ)。
    var debugStartsPlayer = false
    /// 同じく、歌詞が届いた時点で行の区切りの編集に入る (DEBUG のみ)。
    var debugStartsStructure = false
    /// 同じく、歌詞が届いた時点でタイミング編集をパートの段で開く (DEBUG のみ)。
    var debugStartsParts = false
    #endif

    /// 非 nil = 編集モード。編集中の状態はここが持つ (元の `Lyrics` は不変)。
    @State private var editor: CallGuideEditorModel?
    @State private var callRequest: CallEditorSheet.Request?
    /// アンカーの選び直し中のコール。選択待ちであることを画面に出す。
    @State private var reanchorTarget: ReanchorTarget?
    /// 選択待ち状態をまとめて解除するための合図 (シートを閉じた後など)。
    @State private var selectionResetToken = 0
    @State private var saveErrorMessage: String?
    /// 非 nil = タイミング編集を開いている。
    @State private var recorder: LyricTimingRecorder?
    /// 歌詞プレイヤーを開いている。
    @State private var showsPlayer = false
    /// 開いたプレイヤーが、いま鳴っている曲に付いていく方か (プレイリストの途中で開いたとき)。
    @State private var playerFollowsQueue = false
    /// 行の区切りを編集している (くっつける / 切り離す)。
    @State private var isEditingStructure = false
    /// 区切りの変更を送っている行 (二度押しを止める)。
    @State private var structureBusyLineId: String?
    /// 振り仮名を振る字を選んでいる候補 (選ぶダイアログを出す)。
    @State private var rubyBasePick: RubyBasePick?
    /// 再生に追従している今の行。
    @State private var activeLineId: String?
    /// 記録を始められなかったときの案内。
    @State private var recordUnavailable = false
    /// ダブルタップの手応え (付け外しのたびに増やす)。
    @State private var likeToken = 0
    /// 付け外しの後にサーバが返した行の人数 (みんなの分)。歌詞を取り直すまでこちらを優先する。
    @State private var likeCounts: [String: Int] = [:]

    private var markService: UserMarkService { UserMarkService.shared }

    private struct ReanchorTarget: Equatable {
        let lineId: String
        let callId: String
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            ImasSignInPrompt(message: "歌詞の表示にはログインが必要です")
            content
            // 歌詞が実際に出ているときだけ掲示する。読み込み中やエラーの画面に
            // 許諾番号だけが残っていると、何に対する許諾なのか分からなくなる。
            if vm.lyrics != nil {
                JASRACLicenseNotice(placement: .lyrics)
            }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
        // フル再生中の曲なら、再生中バーから今の行・歌詞プレイヤーを出せるよう預ける (メモリだけ)。
        .task(id: SessionKey(playback: MusicKitService.shared.playbackKey, lyrics: vm.lyrics,
                             artists: vm.originalArtists.map(\.id))) {
            guard let lyrics = vm.lyrics else { return }
            LyricsSession.shared.register(.init(
                song: song, seed: seed, artistLine: vm.artistLine(for: song),
                artworkURL: vm.artworkInfo?.artworkURL ?? song.artworkUrl.flatMap(URL.init(string:)),
                lyrics: lyrics, cast: partCast))
        }
        .sheet(item: $callRequest) { request in
            CallEditorSheet(
                request: request,
                seed: seed,
                onSubmit: { text, emphasis, timing in
                    apply(request, text: text, emphasis: emphasis, timing: timing)
                },
                onDelete: request.existing.map { call in
                    { editor?.deleteCall(lineId: request.lineId, callId: call.id) }
                }
            )
        }
        .confirmationDialog("「\(rubyBasePick?.choice.reading ?? "")」を振る字", isPresented: Binding(
            get: { rubyBasePick != nil }, set: { if !$0 { rubyBasePick = nil } }
        ), titleVisibility: .visible, presenting: rubyBasePick) { pick in
            ForEach(pick.choice.bases, id: \.self) { base in
                Button(base == pick.choice.base && pick.choice.isRuby ? "「\(pick.baseText(base))」(いま)" : "「\(pick.baseText(base))」") {
                    applyRubyBase(pick, base: base)
                }
            }
        }
        .alert("保存できませんでした", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .alert("タイミングを記録できません", isPresented: $recordUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("記録には Apple Music でのフル再生が必要です。")
        }
        // 再生位置を読みに行くのは、追従か記録で使うときだけ。
        .task(id: followKey) { await followPlayback() }
        .onChange(of: activeLineId) { _, id in
            if let id, recorder == nil { playback.scrollTo(id) }
        }
        .fullScreenCover(item: $recorder) { recorder in
            if let lyrics = vm.lyrics {
                LyricTimingEditorView(song: song, seed: seed, lyrics: lyrics, playback: playback,
                                      recorder: recorder, onSaved: reload, cast: partCast)
            }
        }
        .fullScreenCover(isPresented: $showsPlayer) {
            if playerFollowsQueue {
                // 曲を順に鳴らしている最中は、曲送りで替わった曲にも付いていく方を開く。
                NowPlayingLyricsPlayerView { nowSong in
                    showsPlayer = false
                    if nowSong.id == song.id, let lyrics = vm.lyrics { Task { await beginRecording(lyrics) } }
                }
            } else if let lyrics = vm.lyrics {
                LyricsPlayerView(song: song, seed: seed, artistLine: vm.artistLine(for: song),
                                 artworkURL: vm.artworkInfo?.artworkURL ?? song.artworkUrl.flatMap(URL.init(string:)),
                                 lyrics: lyrics, playback: playback, likeCounts: $likeCounts,
                                 onEditTimings: {
                                     showsPlayer = false
                                     Task { await beginRecording(lyrics) }
                                 },
                                 cast: partCast)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: likeToken)
        #if DEBUG
        .onChange(of: vm.lyrics) { _, lyrics in beginDebugEditingIfNeeded(lyrics) }
        .onAppear { beginDebugEditingIfNeeded(vm.lyrics) }
        #endif
    }

    #if DEBUG
    private func beginDebugEditingIfNeeded(_ lyrics: Lyrics?) {
        guard let lyrics else { return }
        if debugStartsRecording || debugStartsParts, recorder == nil {
            let r = LyricTimingRecorder(lyrics: lyrics, songId: song.id)
            switch debugStartsParts ? "parts" : ProcessInfo.processInfo.environment["TIMING_LANE"] {
            case "parts": r.lane = .parts
            case "calls": r.lane = .calls
            default: break
            }
            recorder = r
        }
        if debugStartsPlayer, !showsPlayer { showsPlayer = true }
        if debugStartsStructure { isEditingStructure = true }
        guard debugStartsEditing, editor == nil else { return }
        editor = CallGuideEditorModel(lyrics: lyrics, songId: song.id)
    }
    #endif

    @ViewBuilder
    private var content: some View {
        switch vm.serverDataState {
        case .loading:
            ImasInlineLoading()
        case .failed(let message):
            ImasEmptyState(systemImage: "exclamationmark.triangle",
                           title: "歌詞を表示できません",
                           message: message,
                           actionTitle: "再試行",
                           action: reload,
                           seed: seed)
        case .loaded:
            if let lyrics = vm.lyrics, lyrics.hasContent {
                // 未公開 (draft) はサーバが admin にしか返さない。公開済みと
                // 取り違えないよう画面に明示する。JASRAC の許諾が下りるまで
                // 一般ユーザーには配信されない。
                if lyrics.isDraft {
                    ImasBadge(text: "下書き（未公開）。この表示は管理者のみ", kind: .attention, systemImage: "eye.slash")
                        .padding(.horizontal, DS.sp1)
                }
                editBar(lyrics)
                if isEditingStructure {
                    ImasNote("語をタップすると、その語の前で行を切り離します。行の右下の鎖のボタンで次の行とくっつけます。歌詞の文字は変わりません。",
                             systemImage: "scissors")
                        .padding(.horizontal, DS.sp1)
                    card { structureBody(lyrics) }
                } else if let editor {
                    editingBanner
                    staleSection(editor)
                    card { editingBody(editor) }
                } else {
                    card { viewingBody(lyrics) }
                }
                if let source = lyrics.source, !source.isEmpty {
                    ImasNote("出典: \(source)")
                        .padding(.horizontal, DS.sp1)
                }
            } else {
                emptyState
            }
        }
    }

    /// 歌詞が無い時の空状態。未ログインは「無い」のではなく「見られない」ので文言を分ける
    /// (未ログインでは束ねの歌詞が常に null で返る)。
    @ViewBuilder
    private var emptyState: some View {
        if AuthService.shared.isSignedIn {
            ImasEmptyState(systemImage: "text.quote",
                           title: "歌詞はまだありません",
                           message: "この曲の歌詞はまだ登録されていません。",
                           seed: seed)
        } else {
            ImasEmptyState(systemImage: "text.quote",
                           title: "歌詞の表示にはログインが必要です",
                           message: "ログインすると、登録済みの曲の歌詞を表示できます。",
                           seed: seed)
        }
    }

    // MARK: - カード

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ImasCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(song.title).imasText(.cardTitle).padding(.bottom, DS.sp2)
                if let artistLine = vm.artistLine(for: song), !artistLine.isEmpty {
                    Text(artistLine).imasText(.note).padding(.bottom, DS.sp3)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 閲覧

    @ViewBuilder
    private func viewingBody(_ lyrics: Lyrics) -> some View {
        legend(lyrics)
        likeHeatBar(lyrics)
        let likes = markService.lyricLikes(songId: song.id)
        if likes.isEmpty {
            // 付け方は見ただけでは分からないので、1 つも付いていない曲でだけ添える。
            ImasNote("好きな行をダブルタップで「ここ好き」", systemImage: "hand.tap")
                .padding(.bottom, DS.sp3)
        }
        let firstFocus = lyrics.lines.first { focusLineIds.contains($0.id) }?.id
        ForEach(lyrics.lines) { line in
            if line.id == firstFocus { focusCaption }
            viewingRow(line, isLiked: likes.contains(line.id))
                .imasLyricLine(line.id == activeLineId ? .current : .normal, seed: seed)
                .modifier(FocusedLineStyle(isFocused: focusLineIds.contains(line.id), seed: seed))
                .id(line.id)
        }
    }

    /// 出題箇所の見出し。色だけに頼らず、何の印なのかを言葉でも出す。
    private var focusCaption: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        return Label("クイズで出題された箇所", systemImage: "quote.bubble.fill")
            .font(.imasCaption2.weight(.semibold))
            .foregroundStyle(t.chipText)
            .padding(.top, DS.sp2)
            .padding(.bottom, DS.sp1)
    }

    /// 凡例は**その曲で実際に使われているものだけ**を出す (曲ごとに凡例が違う)。
    /// 出すものが 1 つも無ければ余白ごと畳む。
    @ViewBuilder
    private func legend(_ lyrics: Lyrics) -> some View {
        let emphases = lyrics.usedEmphases
        let claps = lyrics.usedClaps
        let showsOverTiming = lyrics.usesOverTiming
        if !emphases.isEmpty || !claps.isEmpty || showsOverTiming {
            CallGuideLegend(emphases: emphases, claps: claps, showsOverTiming: showsOverTiming)
                .padding(.bottom, DS.sp4)
        }
    }

    @ViewBuilder
    private func viewingRow(_ line: LyricLine, isLiked: Bool) -> some View {
        switch line.kind {
        case .lyric:
            HStack(alignment: .top, spacing: DS.sp2) {
                CallGuideClapGlyph(clap: line.clap)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    // ⚠️ ここに `.textSelection(.enabled)` / `.imasCopyable` を足さないこと。
                    // 歌う人は字の下に担当色の線で引く (どこから歌う人が変わるかが字の上で分かる)。
                    let parts = partCast.marks(line, scheme: scheme)
                    if ImasRubyText.hasRuby(line.text) || !parts.isEmpty {
                        // 振り仮名・色の線は Text では組めないので CoreText で描く。
                        ImasRubyLabel(attributed: CallGuideText.rubyAttributed(
                            line.text, highlights: highlights(for: line),
                            font: Font.imasScaledUIFont(17), color: UIColor(DS.ink), parts: parts))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(CallGuideText.attributed(line.text, highlights: highlights(for: line)))
                            .font(.imasBody)
                            .foregroundStyle(DS.ink)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ImasPartNames(groups: partCast.groups(line))
                    // 歌詞と同じ文字の同時コールは行に並べない (歌詞のその部分を濃く敷いて示す)。
                    let listed = line.calls.filter { !line.echoes($0) }
                    if !listed.isEmpty {
                        CallGuideCallRows(calls: listed, anchorIndexes: anchorIndexes(for: line))
                    }
                }
                if isLiked {
                    ImasLyricLikeMark(seed: seed).padding(.top, DS.sp1)
                }
            }
            .padding(.vertical, 3)
            // 行のどこをダブルタップしても付け外しできるように、余白も当たりにする。
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { toggleLike(line) }
            .accessibilityAction(named: isLiked ? "ここ好きを外す" : "ここ好き") { toggleLike(line) }
        case .marker:
            VStack(alignment: .leading, spacing: 0) {
                marker(line.text)
                if !line.calls.isEmpty {
                    CallGuideCallRows(calls: line.calls, anchorIndexes: nil)
                        .padding(.bottom, DS.sp3)
                }
            }
        case .blank:
            Color.clear.frame(height: DS.sp5)
        }
    }

    /// 「イントロ」「サビ」等の構成マーカー。歌詞本文と混ざらないよう罫線で挟んだ細いラベルにする。
    private func marker(_ text: String) -> some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        return HStack(spacing: DS.sp3) {
            rule
            Text(text)
                .font(.imasCaption2.weight(.semibold))
                .foregroundStyle(t.chipText)
                .lineLimit(1)
            rule
        }
        .padding(.vertical, DS.sp3)
        .accessibilityLabel("セクション: \(text)")
    }

    private var rule: some View {
        Rectangle().fill(DS.sep).frame(height: 1)
    }

    // MARK: - 編集への出入り

    /// コールガイドを編集してよいか。
    ///
    /// **ログインしていれば誰でも書ける。** コールはユーザーが書くもので、タグと同じ扱い。
    ///
    /// サーバ側 (`PUT /songs/:id/calls`) もログイン + `is_banned` + 編集レート枠で通す。
    /// あの経路では**歌詞本文を書き換えられない**構造 (行 ID と clap/calls しか受け取らず、
    /// 本文は D1 の既存行が唯一の正) なので、開けても歌詞は守られる。
    ///
    /// 許諾が下りるまでは admin 限定だった。歌詞そのものが admin にしか返らなかったので
    /// 分ける意味が無かったが、公開した今はその前提が消えている。
    private var canEdit: Bool {
        #if DEBUG
        // サーバ未実装でも編集の見た目を確認できるようにする (FAKE_LYRICS は DEBUG 限定)。
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" { return true }
        #endif
        return AuthService.shared.isSignedIn
    }

    @ViewBuilder
    private func editBar(_ lyrics: Lyrics) -> some View {
        if canEdit {
            HStack(spacing: DS.sp3) {
                Spacer(minLength: 0)
                if isEditingStructure {
                    ImasButton(title: "区切りの編集を終了", role: .plain, size: .small) {
                        isEditingStructure = false
                    }
                } else if let editor {
                    ImasButton(title: "編集を終了", role: .plain, size: .small) {
                        self.editor = nil
                        reanchorTarget = nil
                    }
                    saveButton(editor)
                } else {
                    ImasIconButton(systemImage: "scissors", label: "行の区切りを編集", size: .small) {
                        AppAnalytics.tap("lyric_structure.begin_edit")
                        isEditingStructure = true
                    }
                    ImasIconButton(systemImage: "music.note.list", label: "歌詞プレイヤー",
                                   size: .small) {
                        AppAnalytics.tap("lyrics_player.open")
                        playerFollowsQueue = MusicKitService.shared.hasQueue
                            && MusicKitService.shared.nowPlayingSongId == song.id
                        showsPlayer = true
                    }
                    // 歌詞の時刻・コールの時刻・パート分けは、どれもこの 1 つの入口から (段を切り替える)。
                    ImasIconButton(systemImage: "metronome", label: "タイミング・パートを編集",
                                   size: .small) {
                        AppAnalytics.tap("lyric_timing.begin_record")
                        Task { await beginRecording(lyrics) }
                    }
                    ImasButton(title: lyrics.hasCalls ? "コールを編集" : "コールを付ける",
                              systemImage: "square.and.pencil", role: .secondary, size: .small) {
                        AppAnalytics.tap("call_guide.begin_edit")
                        editor = CallGuideEditorModel(lyrics: lyrics, songId: song.id)
                    }
                }
            }
            .padding(.horizontal, DS.sp1)
        }
    }

    private func saveButton(_ editor: CallGuideEditorModel) -> some View {
        ImasButton(title: "保存", role: .primary, size: .small, isLoading: editor.saveState == .saving) {
            AppAnalytics.tap("call_guide.save")
            Task { await save(editor) }
        }
        .disabled(!editor.isDirty || editor.saveState == .saving)
    }

    private func save(_ editor: CallGuideEditorModel) async {
        guard await editor.save() else {
            if case .failed(let message) = editor.saveState { saveErrorMessage = message }
            return
        }
        // 曲一覧の「コールガイドがある曲のみ」に、取り直しを待たずに載せる (外したなら外す)。
        let hasCalls = editor.lines.contains { !$0.calls.isEmpty || $0.clap != nil }
        await LyricAnnotationStore.shared.mark(songId: song.id, .calls, hasCalls)
        // サーバが id を付け直したり stale を再計算したりするので、保存後は取り直す。
        self.editor = nil
        reanchorTarget = nil
        reload()
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
    }

    // MARK: - 編集

    @ViewBuilder
    private var editingBanner: some View {
        if let target = reanchorTarget {
            ImasNotice(kind: .warning,
                      message: "「\(target.text)」の掛かる範囲を選び直しています。語をタップ、または長押しからなぞる。",
                      actionTitle: "やめる", action: { reanchorTarget = nil })
        } else {
            // 多数派 (追っかけ) の導線を先に書く。被せるコールの範囲選択はその次。
            ImasNote("歌詞の語をタップすると、その語に被せるコールを付けられます。行末の ＋ は追っかけ、行頭の記号は手拍子。語をまたぐ範囲は長押しからなぞって選びます。",
                    systemImage: "hand.tap")
                .padding(.horizontal, DS.sp1)
        }
    }

    /// 歌詞が編集されてアンカーがズレたコール。放置すると別の語に掛かって見えるので、
    /// 編集モードの先頭にまとめて出して選び直させる。
    @ViewBuilder
    private func staleSection(_ editor: CallGuideEditorModel) -> some View {
        let stale = editor.staleCalls
        let theme = ImasTheme.derive(seed: seed, scheme: scheme)
        if !stale.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                // 見出しだけ (前は Label のみ)。「語をタップで選び直せる」という文言は、
                // ここではまだ reanchorTarget が立っていないため実際には新規コール作成を
                // 開いてしまい誤り。選び直しは各行の「選び直す」ボタンからのみ行える。
                ImasNotice(kind: .warning, title: "アンカーがズレたコール（\(stale.count) 件）")
                ImasCardList {
                    ForEach(Array(stale.enumerated()), id: \.element.call.id) { idx, entry in
                        if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                        let attributedTitle: AttributedString = {
                            var title = AttributedString(entry.call.text)
                            title.foregroundColor = entry.call.emphasis.color(accent: theme.accent)
                            return title
                        }()
                        ImasRow(
                            title: entry.call.text,
                            subtitle: "元のアンカー: \(entry.call.anchorText.isEmpty ? "（なし）" : entry.call.anchorText)",
                            trailing: .custom(AnyView(
                                Button("選び直す") {
                                    reanchorTarget = ReanchorTarget(lineId: entry.line.id, callId: entry.call.id,
                                                                    text: entry.call.text)
                                    selectionResetToken += 1
                                }
                                .font(.imasCaption.weight(.semibold))
                            )),
                            density: .compact,
                            attributedTitle: attributedTitle
                        ) {
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editingBody(_ editor: CallGuideEditorModel) -> some View {
        ForEach(editor.lines) { line in
            editingRow(editor, line)
        }
    }

    @ViewBuilder
    private func editingRow(_ editor: CallGuideEditorModel, _ line: LyricLine) -> some View {
        switch line.kind {
        case .lyric:
            HStack(alignment: .top, spacing: 0) {
                clapMenu(editor, line)
                VStack(alignment: .leading, spacing: 0) {
                    CallGuideSelectableLine(
                        text: line.text,
                        highlights: highlights(for: line),
                        onSelect: { start, end, selected in
                            handleSelection(line: line, start: start, end: end, text: selected)
                        },
                        // 選び直し中は範囲を選ばせたいので行末の ＋ は出さない。
                        onAppendCall: reanchorTarget == nil ? { appendTrailingCall(line) } : nil,
                        resetToken: selectionResetToken
                    )
                    if !line.calls.isEmpty {
                        CallGuideCallRows(calls: line.calls,
                                          anchorIndexes: anchorIndexes(for: line),
                                          onTap: { call in editCall(line: line, call: call) })
                    }
                }
            }
            .padding(.vertical, 1)
        case .marker:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.sp3) {
                    clapMenu(editor, line)
                    marker(line.text)
                    // marker 行 (イントロ / 間奏) にも歌詞行と同じ導線を出す。
                    // 「（間奏）(Hi!) × 26」のような歌詞のないコールが実際に多い。
                    CallGuideAppendCallButton { appendTrailingCall(line) }
                }
                if !line.calls.isEmpty {
                    CallGuideCallRows(calls: line.calls, anchorIndexes: nil,
                                      onTap: { call in editCall(line: line, call: call) })
                        .padding(.bottom, DS.sp3)
                }
            }
        case .blank:
            Color.clear.frame(height: DS.sp5)
        }
    }

    private func clapMenu(_ editor: CallGuideEditorModel, _ line: LyricLine) -> some View {
        Menu {
            Button("指定なし") { editor.setClap(lineId: line.id, clap: nil) }
            ForEach(LyricClap.allCases, id: \.self) { clap in
                Button("\(clap.symbol) \(clap.label)") { editor.setClap(lineId: line.id, clap: clap) }
            }
        } label: {
            CallGuideClapGlyph(clap: line.clap, isPlaceholderVisible: true)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
    }

    // MARK: - 編集操作

    /// 範囲が選ばれたとき。選び直し中ならそのコールの付け替え、そうでなければ新規追加。
    private func handleSelection(line: LyricLine, start: Int, end: Int, text: String) {
        if let target = reanchorTarget {
            editor?.reanchor(callId: target.callId, from: target.lineId, to: line.id,
                             start: start, end: end, anchorText: text)
            reanchorTarget = nil
            return
        }
        callRequest = CallEditorSheet.Request(lineId: line.id, start: start, end: end,
                                              anchorText: text, lineText: line.text, existing: nil)
    }

    /// 行末 (追っかけ) にコールを足す。範囲を選ばせず 1 タップでシートまで飛ばす。
    ///
    /// アイマスのコールは**フレーズの後で客が返す**追っかけが多数派で、歌詞に被せるものは
    /// 少数派。多数派を範囲選択の後ろに置くのは手数が合わない。
    /// アンカーは `start == end == 行の文字数` の幅ゼロ。サーバは `start <= end` を許し、
    /// `anchorText` は本文から切り出した空文字になる。
    private func appendTrailingCall(_ line: LyricLine) {
        AppAnalytics.tap("call_guide.add_trailing")
        let end = CallGuideText.scalarCount(of: line.text)
        callRequest = CallEditorSheet.Request(lineId: line.id, start: end, end: end,
                                              anchorText: "", lineText: line.text, existing: nil)
        // 範囲選択の途中 (開始だけタップ済み) なら取り消す。
        selectionResetToken += 1
    }

    private func editCall(line: LyricLine, call: LyricCall) {
        callRequest = CallEditorSheet.Request(lineId: line.id, start: call.start, end: call.end,
                                              anchorText: call.anchorText, lineText: line.text,
                                              existing: call)
    }

    private func apply(_ request: CallEditorSheet.Request, text: String,
                       emphasis: CallEmphasis, timing: CallTiming) {
        guard let editor else { return }
        if let existing = request.existing {
            editor.updateCall(lineId: request.lineId, callId: existing.id,
                              text: text, emphasis: emphasis, timing: timing)
        } else {
            editor.addCall(lineId: request.lineId, start: request.start, end: request.end,
                           anchorText: request.anchorText, text: text,
                           emphasis: emphasis, timing: timing)
        }
        selectionResetToken += 1
    }

    // MARK: - 再生との連動 (追従・タイミング記録)

    /// 表示順の各行の開始 ms。
    private func starts(_ lyrics: Lyrics) -> [Int64?] {
        lyrics.lines.map { $0.startMs.map(Int64.init) }
    }

    /// 今の行に追従するか。フル再生中で、記録が足りていて、編集・記録をしていないときだけ
    /// (記録中は「次の行」の印と紛れるので今の行は出さない)。
    private var followsPlayback: Bool {
        guard playback.isFullLoaded, editor == nil, recorder == nil, let lyrics = vm.lyrics else { return false }
        return lyricHasTiming(starts: starts(lyrics))
    }

    /// 再生位置を読む周期処理を張り直す鍵。追従しないなら読まない。
    private var followKey: String { "\(followsPlayback)|\(vm.lyrics?.updatedAt ?? 0)" }

    /// フル再生の位置を周期で読み、今の行を出す。
    private func followPlayback() async {
        guard followsPlayback, let lyrics = vm.lyrics else {
            activeLineId = nil
            return
        }
        let starts = starts(lyrics)
        while !Task.isCancelled {
            if let ms = playback.positionMs() {
                let index = lyricActiveLine(starts: starts, positionMs: Int64(ms)).map(Int.init)
                let id = index.map { lyrics.lines[$0].id }
                if id != activeLineId { activeLineId = id }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// タイミング編集を開く。この曲がフル尺で読み込まれていなければ頭から鳴らす。
    /// 鳴らせなくても、パート分けは聴かずに塗れるので、パートの段で開く (原唱者が 2 人以上のとき)。
    private func beginRecording(_ lyrics: Lyrics) async {
        var lane = LyricTimingRecorder.Lane.lines
        if !playback.isFullLoaded, !(await playback.startFull()) {
            guard !partCast.artists.isEmpty else {
                recordUnavailable = true
                return
            }
            lane = .parts
        }
        let recorder = LyricTimingRecorder(lyrics: lyrics, songId: song.id)
        recorder.lane = lane
        self.recorder = recorder
    }

    /// 再生中バーへ預け直す契機 (再生状態・歌詞・原唱者のどれかが変わったとき)。
    private struct SessionKey: Equatable {
        let playback: String
        let lyrics: Lyrics?
        let artists: [String]
    }

    // MARK: - パート分け (誰が歌うか)

    /// 帯の色・名前を原唱者から引く表。
    /// ソロ曲 (原唱者 1 人) では空にして、帯も名前も出さない。
    private var partCast: LyricPartCast {
        lyricPartsApplicable(originalArtistCount: UInt32(vm.originalArtists.count))
            ? LyricPartCast(artists: vm.originalArtists) : .empty
    }

    // MARK: - 行の区切り (くっつける / 切り離す)

    @ViewBuilder
    private func structureBody(_ lyrics: Lyrics) -> some View {
        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
            switch line.kind {
            case .lyric:
                VStack(alignment: .leading, spacing: DS.sp1) {
                    // 語をタップ → その語の前で切る。行頭の語は切れないので何もしない。
                    CallGuideSelectableLine(
                        text: line.text, highlights: [],
                        onSelect: { start, _, _ in
                            guard start > 0 else { return }
                            Task { await changeStructure(line.id, .split(lineId: line.id, at: start)) }
                        }
                    )
                    .opacity(structureBusyLineId == line.id ? 0.4 : 1)
                    rubyToggles(line)
                    if index + 1 < lyrics.lines.count, lyrics.lines[index + 1].kind == .lyric {
                        HStack {
                            Spacer(minLength: 0)
                            Menu {
                                ForEach(LyricStructurePayload.Joiner.allCases, id: \.self) { joiner in
                                    Button(joiner.label) {
                                        Task { await changeStructure(line.id, .merge(lineId: line.id, joiner: joiner)) }
                                    }
                                }
                            } label: {
                                Label("次の行とくっつける", systemImage: "link")
                                    .labelStyle(.iconOnly)
                                    .imasText(.meta)
                                    .frame(minWidth: DS.Size.touch, minHeight: DS.Size.touch)
                                    .contentShape(Rectangle())
                            }
                            .disabled(structureBusyLineId != nil)
                        }
                    }
                }
            case .marker:
                marker(line.text)
            case .blank:
                Color.clear.frame(height: DS.sp5)
            }
        }
    }

    /// 行の中の振り仮名 (《》) と、振り仮名にできる括弧を並べる (候補の規則はコアの `lyricRubyChoices`)。
    /// 親字の頭は選べる (当て字や、漢字のまとまりの一部だけに掛けるとき)。
    @ViewBuilder
    private func rubyToggles(_ line: LyricLine) -> some View {
        let choices = lyricRubyChoices(text: line.text)
        if !choices.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp2) {
                    ForEach(choices, id: \.open) { choice in
                        let at = Int(choice.open)
                        if choice.isRuby {
                            ImasButton(title: "「\(choice.reading)」をルビにしない", systemImage: "textformat",
                                       role: .plain, size: .small) {
                                Task { await changeStructure(line.id, .unruby(lineId: line.id, at: at)) }
                            }
                            .disabled(structureBusyLineId != nil)
                            if choice.bases.count > 1 {
                                ImasButton(title: "「\(choice.reading)」を振る字を選ぶ", systemImage: "character.cursor.ibeam",
                                           role: .plain, size: .small) {
                                    rubyBasePick = RubyBasePick(lineId: line.id, text: line.text, choice: choice)
                                }
                                .disabled(structureBusyLineId != nil)
                            }
                        } else {
                            ImasButton(title: "「\(choice.reading)」をルビにする", systemImage: "textformat.superscript",
                                       role: .plain, size: .small) {
                                // 漢字の直後なら漢字のまとまりに振る (違えば「振る字を選ぶ」で直す)。当て字は選んでもらう。
                                if choice.base != nil {
                                    Task { await changeStructure(line.id, .ruby(lineId: line.id, at: at)) }
                                } else {
                                    rubyBasePick = RubyBasePick(lineId: line.id, text: line.text, choice: choice)
                                }
                            }
                            .disabled(structureBusyLineId != nil)
                        }
                    }
                }
            }
        }
    }

    /// 振り仮名を振る字を選んでいる最中の候補。
    struct RubyBasePick: Identifiable {
        let lineId: String
        let text: String
        let choice: LyricRubyChoice
        var id: String { "\(lineId)#\(choice.open)" }

        /// 親字の頭を `base` にしたときの親字 (｜は除く)。
        func baseText(_ base: UInt32) -> String {
            let scalars = Array(text.unicodeScalars)
            return String(String.UnicodeScalarView(scalars[Int(base)..<Int(choice.open)].filter { $0 != "｜" }))
        }
    }

    /// 振る字を選んだら送る。
    private func applyRubyBase(_ pick: RubyBasePick, base: UInt32) {
        let at = Int(pick.choice.open)
        let change: LyricStructurePayload = pick.choice.isRuby
            ? .rubyBase(lineId: pick.lineId, at: at, base: Int(base))
            : .ruby(lineId: pick.lineId, at: at, base: Int(base))
        Task { await changeStructure(pick.lineId, change) }
    }

    /// 区切りの変更を送り、歌詞を取り直す。文字は変わらない (行 ID と位置だけを送る)。
    private func changeStructure(_ lineId: String, _ change: LyricStructurePayload) async {
        guard structureBusyLineId == nil else { return }
        AppAnalytics.tap("lyric_structure.\(change.op)")
        structureBusyLineId = lineId
        defer { structureBusyLineId = nil }
        do {
            try await AppContainer.shared.callGuideWriting.editLyricStructure(songId: song.id, change)
            reload()
        } catch {
            saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - ここ好き

    /// 行の「ここ好き」を付け外しする (中身は `LyricLikeAction`、歌詞プレイヤーと同じ)。
    private func toggleLike(_ line: LyricLine) {
        likeToken += 1
        Task {
            if let count = await LyricLikeAction.toggle(songId: song.id, lineId: line.id) {
                likeCounts[line.id] = count
            }
        }
    }

    // MARK: - ここ好きの山

    /// みんなの「ここ好き」を曲の時間軸の山にしたシークバー。タップした位置から鳴らす。
    ///
    /// 山を立てるには行の時刻が要る (記録の無い曲では出さない)。山がまだ無くても、
    /// フル再生中ならシークバーとして出す。
    @ViewBuilder
    private func likeHeatBar(_ lyrics: Lyrics) -> some View {
        let starts = starts(lyrics)
        if recorder == nil, editor == nil, lyricHasTiming(starts: starts) {
            let counts = lyrics.lines.map { UInt32(max(0, likeCounts[$0.id] ?? $0.likeCount)) }
            let lastStart = starts.compactMap { $0 }.max() ?? 0
            let duration = playback.durationMs()
                ?? song.durationSec.map { $0 * 1000 }
                ?? Int(lastStart) + 8000
            let heat = lyricLikeHeat(starts: starts, counts: counts,
                                     durationMs: Int64(duration), buckets: 60)
            if playback.isFullLoaded || !heat.levels.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp1) {
                    if !heat.levels.isEmpty {
                        Text("みんなのここ好き").imasText(.meta)
                    }
                    // 進みの線だけを周期で描き直す。
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        ImasLikeHeatSeekBar(
                            levels: heat.levels,
                            progress: playback.isFullLoaded
                                ? playback.positionMs().map { Double($0) / Double(duration) } : nil,
                            peak: heat.peakMs.map { Double($0) / Double(duration) },
                            seed: seed
                        ) { fraction in
                            AppAnalytics.tap("lyric_like.heat_seek")
                            Task { await playback.playFrom(Int(fraction * Double(duration))) }
                        }
                    }
                }
                .padding(.bottom, DS.sp4)
            }
        }
    }

    // MARK: - アンカーの見せ方

    /// 行内のアンカーごとの色。同じ範囲に複数のコールが載っているときは、
    /// **強い方**の色で敷く (演者要望 > おこのみで > 通常)。弱い方に埋もれさせない。
    private func highlights(for line: LyricLine) -> [CallGuideText.Highlight] {
        let theme = ImasTheme.derive(seed: seed, scheme: scheme)
        var order: [String] = []
        var strongest: [String: LyricCall] = [:]
        for call in line.calls where call.hasAnchor {
            let key = "\(call.start)-\(call.end)"
            guard let current = strongest[key] else {
                order.append(key)
                strongest[key] = call
                continue
            }
            if rank(call.emphasis) > rank(current.emphasis) { strongest[key] = call }
        }
        var result = order.compactMap { key in
            strongest[key].map { call in
                CallGuideText.Highlight(start: call.start, end: call.end,
                                        color: anchorColor(call.emphasis, theme: theme),
                                        isEcho: editor == nil && line.calls.contains {
                                            $0.start == call.start && $0.end == call.end && line.echoes($0)
                                        })
            }
        }
        // いま編集中のアンカーを最後に重ねる。シートは `.medium` で開くので歌詞の
        // 上半分は見えたままで、そこに「どこに掛けようとしているか」が出ていないと
        // 何を選んだのか分からない (タップで即シートが開くので、なぞりのような
        // 途中経過も残らない)。色はなぞり中と同じアクセントにして、確定済みの
        // アンカー (淡い) と見分けられるようにする。
        if let pending = callRequest, pending.lineId == line.id, pending.hasAnchor {
            result.append(CallGuideText.Highlight(start: pending.start, end: pending.end,
                                                  color: theme.accent, isPending: true))
        }
        return result
    }

    private func anchorColor(_ emphasis: CallEmphasis, theme: ImasTheme) -> Color {
        // 通常のコールは本文色で敷くと「文字が濃くなっただけ」に見えるので、
        // 曲の配色 (担当色 / ブランド色) を使って「範囲」だと分かるようにする。
        // コール文言側も同じ色を使う (CallEmphasis.color(accent:))。
        emphasis.color(accent: theme.accent)
    }

    private func rank(_ emphasis: CallEmphasis) -> Int {
        switch emphasis {
        case .normal:           return 0
        case .optional:         return 1
        case .performerRequest: return 2
        }
    }

    /// 同じ行に複数のアンカーがあるときだけ ①②③ を振る。1 つしか無い行に番号を振っても
    /// 情報が増えないので nil を返す (その場合コール行は「↳」で示す)。
    private func anchorIndexes(for line: LyricLine) -> [String: Int]? {
        var groups: [String: Int] = [:]
        var result: [String: Int] = [:]
        var order = 0
        // 行に並べない (歌詞と同じ文字の同時) コールは番号を振る数に入れない。
        for call in line.calls where call.hasAnchor && (editor != nil || !line.echoes(call)) {
            let key = "\(call.start)-\(call.end)"
            if groups[key] == nil {
                groups[key] = order
                order += 1
            }
            result[call.id] = groups[key]
        }
        return order > 1 ? result : nil
    }
}

/// 出題箇所の行に敷く帯。カードの余白へ少しはみ出させて、本文の折り返し位置は変えない。
private struct FocusedLineStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let isFocused: Bool
    let seed: String?

    func body(content: Content) -> some View {
        if isFocused {
            let t = ImasTheme.derive(seed: seed, scheme: scheme)
            content
                .padding(.horizontal, DS.sp2)
                .background(t.accent.opacity(scheme == .dark ? 0.24 : 0.14),
                            in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                .overlay(alignment: .leading) {
                    Capsule().fill(t.accent).frame(width: 3).padding(.vertical, 4)
                }
                .padding(.horizontal, -DS.sp2)
                .accessibilityHint("クイズで出題された行")
        } else {
            content
        }
    }
}

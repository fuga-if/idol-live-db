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
    @Environment(\.colorScheme) private var scheme

    let song: Song
    /// 配色シード (ソロ曲は担当色、それ以外はブランド色)。
    let seed: String?
    let vm: DetailSheetViewModel
    /// 通信失敗時の再試行 (束ね取得のやり直し)。
    let reload: () -> Void

    #if DEBUG
    /// スクリーンショット検証用に、歌詞が届いた時点で編集モードに入る (DEBUG ビルドのみ)。
    /// `CallGuidePreviewHarness` からしか渡らない。Release ビルドにはこの口自体が存在しない。
    var debugStartsEditing = false
    #endif

    /// 非 nil = 編集モード。編集中の状態はここが持つ (元の `Lyrics` は不変)。
    @State private var editor: CallGuideEditorModel?
    @State private var callRequest: CallEditorSheet.Request?
    /// アンカーの選び直し中のコール。選択待ちであることを画面に出す。
    @State private var reanchorTarget: ReanchorTarget?
    /// 選択待ち状態をまとめて解除するための合図 (シートを閉じた後など)。
    @State private var selectionResetToken = 0
    @State private var saveErrorMessage: String?

    private struct ReanchorTarget: Equatable {
        let lineId: String
        let callId: String
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            InlineLoginPrompt(message: "歌詞の表示にはログインが必要です", seed: seed)
            content
            // 歌詞が実際に出ているときだけ掲示する。読み込み中やエラーの画面に
            // 許諾番号だけが残っていると、何に対する許諾なのか分からなくなる。
            if vm.lyrics != nil {
                JASRACLicenseNotice(placement: .lyrics)
            }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
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
        .alert("保存できませんでした", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        #if DEBUG
        .onChange(of: vm.lyrics) { _, lyrics in beginDebugEditingIfNeeded(lyrics) }
        .onAppear { beginDebugEditingIfNeeded(vm.lyrics) }
        #endif
    }

    #if DEBUG
    private func beginDebugEditingIfNeeded(_ lyrics: Lyrics?) {
        guard debugStartsEditing, editor == nil, let lyrics else { return }
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
                    Label("下書き（未公開）。この表示は管理者のみ",
                          systemImage: "eye.slash")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .padding(.horizontal, DS.sp2)
                        .padding(.vertical, DS.sp1)
                        .background(DS.ink3.opacity(0.12), in: Capsule())
                        .padding(.horizontal, DS.sp1)
                }
                editBar(lyrics)
                if let editor {
                    editingBanner
                    staleSection(editor)
                    card { editingBody(editor) }
                } else {
                    card { viewingBody(lyrics) }
                }
                if let source = lyrics.source, !source.isEmpty {
                    Text("出典: \(source)")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
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
        VStack(alignment: .leading, spacing: 0) {
            Text(song.title)
                .font(.imasTitle3.weight(.bold))
                .foregroundStyle(DS.ink)
                .padding(.bottom, DS.sp2)
            if let artistLine = vm.artistLine(for: song), !artistLine.isEmpty {
                Text(artistLine)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .padding(.bottom, DS.sp3)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp5)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }

    // MARK: - 閲覧

    @ViewBuilder
    private func viewingBody(_ lyrics: Lyrics) -> some View {
        legend(lyrics)
        ForEach(lyrics.lines) { line in
            viewingRow(line)
        }
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
    private func viewingRow(_ line: LyricLine) -> some View {
        switch line.kind {
        case .lyric:
            HStack(alignment: .top, spacing: 0) {
                CallGuideClapGlyph(clap: line.clap)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    // ⚠️ ここに `.textSelection(.enabled)` / `.imasCopyable` を足さないこと。
                    Text(CallGuideText.attributed(line.text, highlights: highlights(for: line)))
                        .font(.imasBody)
                        .foregroundStyle(DS.ink)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !line.calls.isEmpty {
                        CallGuideCallRows(calls: line.calls, anchorIndexes: anchorIndexes(for: line))
                    }
                }
            }
            .padding(.vertical, 3)
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
    /// 判定は admin のみ。歌詞そのものがサーバ側で admin にしか返らない (draft) 以上、
    /// クライアントで細かく分ける意味がない。
    private var canEdit: Bool {
        #if DEBUG
        // サーバ未実装でも編集の見た目を確認できるようにする (FAKE_LYRICS は DEBUG 限定)。
        if ProcessInfo.processInfo.environment["FAKE_LYRICS"] == "1" { return true }
        #endif
        return AuthService.shared.isAdmin
    }

    @ViewBuilder
    private func editBar(_ lyrics: Lyrics) -> some View {
        if canEdit {
            HStack(spacing: DS.sp3) {
                Spacer(minLength: 0)
                if let editor {
                    Button("編集を終了") {
                        self.editor = nil
                        reanchorTarget = nil
                    }
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
                    saveButton(editor)
                } else {
                    Button {
                        AppAnalytics.tap("call_guide.begin_edit")
                        editor = CallGuideEditorModel(lyrics: lyrics, songId: song.id)
                    } label: {
                        Label(lyrics.hasCalls ? "コールを編集" : "コールを付ける",
                              systemImage: "square.and.pencil")
                            .font(.imasSubhead.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, DS.sp1)
        }
    }

    private func saveButton(_ editor: CallGuideEditorModel) -> some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        return Button {
            AppAnalytics.tap("call_guide.save")
            Task { await save(editor) }
        } label: {
            Group {
                if editor.saveState == .saving {
                    ProgressView().controlSize(.small).tint(t.onAccent)
                } else {
                    Text("保存").font(.imasSubhead.weight(.semibold))
                }
            }
            .frame(minWidth: 56)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(t.onAccent)
            .background(t.accent.opacity(editor.isDirty ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!editor.isDirty || editor.saveState == .saving)
    }

    private func save(_ editor: CallGuideEditorModel) async {
        guard await editor.save() else {
            if case .failed(let message) = editor.saveState { saveErrorMessage = message }
            return
        }
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
            HStack(spacing: DS.sp3) {
                Image(systemName: "scope").font(.imasCaption)
                Text("「\(target.text)」の掛かる範囲を選び直しています。長押しからなぞる、または文字を 2 回タップ。")
                    .font(.imasCaption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("やめる") { reanchorTarget = nil }
                    .font(.imasCaption.weight(.semibold))
            }
            .foregroundStyle(DS.warning)
            .padding(DS.sp3)
            .background(DS.warning.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
        } else {
            // 多数派 (追っかけ) の導線を先に書く。被せるコールの範囲選択はその次。
            Label("行末の ＋ で追っかけのコールを追加。歌詞に被せるときは長押しからなぞって範囲を選ぶ（文字を 2 回タップでも可）。行頭の記号で手拍子を指定。",
                  systemImage: "hand.tap")
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
                .fixedSize(horizontal: false, vertical: true)
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
                Label("アンカーがズレたコール（\(stale.count) 件）", systemImage: "exclamationmark.triangle.fill")
                    .font(.imasFootnote.weight(.bold))
                    .foregroundStyle(DS.warning)
                ForEach(stale, id: \.call.id) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: DS.sp3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.call.text)
                                .font(.imasFootnote.weight(.semibold))
                                .foregroundStyle(entry.call.emphasis.color(accent: theme.accent))
                            Text("元のアンカー: \(entry.call.anchorText.isEmpty ? "（なし）" : entry.call.anchorText)")
                                .font(.imasCaption2)
                                .foregroundStyle(DS.ink3)
                        }
                        Spacer(minLength: 0)
                        Button("選び直す") {
                            reanchorTarget = ReanchorTarget(lineId: entry.line.id,
                                                            callId: entry.call.id,
                                                            text: entry.call.text)
                            selectionResetToken += 1
                        }
                        .font(.imasCaption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.sp4)
            .background(DS.warning.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
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
                                              anchorText: text, existing: nil)
    }

    /// 行末 (追っかけ) にコールを足す。範囲を選ばせず 1 タップでシートまで飛ばす。
    ///
    /// アイマスのコールは**フレーズの後で客が返す**追っかけが多数派で、歌詞に被せるものは
    /// 少数派。多数派を範囲選択 (2 タップ) の後ろに置くのは手数が合わない。
    /// アンカーは `start == end == 行の文字数` の幅ゼロ。サーバは `start <= end` を許し、
    /// `anchorText` は本文から切り出した空文字になる。
    private func appendTrailingCall(_ line: LyricLine) {
        AppAnalytics.tap("call_guide.add_trailing")
        let end = CallGuideText.scalarCount(of: line.text)
        callRequest = CallEditorSheet.Request(lineId: line.id, start: end, end: end,
                                              anchorText: "", existing: nil)
        // 範囲選択の途中 (開始だけタップ済み) なら取り消す。
        selectionResetToken += 1
    }

    private func editCall(line: LyricLine, call: LyricCall) {
        callRequest = CallEditorSheet.Request(lineId: line.id, start: call.start, end: call.end,
                                              anchorText: call.anchorText, existing: call)
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
        return order.compactMap { key in
            strongest[key].map {
                CallGuideText.Highlight(start: $0.start, end: $0.end,
                                        color: anchorColor($0.emphasis, theme: theme))
            }
        }
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
        for call in line.calls where call.hasAnchor {
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

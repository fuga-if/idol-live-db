import SwiftUI

// =============================================================================
// 名刺の素材 (表に重ねる好きな画像・背景を切り抜いた透過画像) の部品。
//
// ImasStickerThumb             素材 1 枚の小さな札 (透過が分かるように市松の地)。選んだ札は墨の縁。
// ImasTransparencyBackdrop     透過の地 (淡い市松)。切り抜きの見本の下に敷く。
// ImasStickerEditLayer         名刺の上で素材を指で置く層。引いて動かす・つまんで大きさ・2 本指で傾ける。
//                              置き方は紙に対する割合で受け渡し、範囲に収めるのは呼ぶ側 (コアの `cardStickerClamp`)。
// =============================================================================

/// 透過の地 (市松)。透過の画像の下に敷いて、どこが抜けているかを見せる。
struct ImasTransparencyBackdrop: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(DS.surface))
            let cols = Int((size.width / cell).rounded(.up)), rows = Int((size.height / cell).rounded(.up))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                                 with: .color(DS.surface2))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 素材 1 枚の札。
struct ImasStickerThumb: View {
    let url: URL
    var isSelected = false
    var side: CGFloat = 56

    var body: some View {
        ImasMeishiPictureView(picture: .url(url), contentMode: .fit, fallback: Color.clear)
            .padding(DS.Space.gapTight)
            .frame(width: side, height: side)
            .background(ImasTransparencyBackdrop(cell: 6))
            .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rTag, style: .continuous)
                    .strokeBorder(isSelected ? DS.ink : DS.line, lineWidth: isSelected ? 2 : 1)
            )
    }
}

/// 名刺の上で素材を置く層。`size` は名刺の紙を描いている大きさ。素材を押すと選び、選んだ素材 (無ければ押した素材) を
/// 指で動かせる。2 本指のつまみ・ひねりは選んでいる素材に効く。
struct ImasStickerEditLayer: View {
    let stickers: [ImasMeishiSticker]
    @Binding var selection: String?
    let size: CGSize
    /// 置き直した素材 (指を離したとき)。
    let onChange: (ImasMeishiSticker) -> Void

    @State private var live: ImasMeishiSticker?
    @State private var dragStart: ImasMeishiSticker?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            ForEach(stickers) { base in
                let s = live?.id == base.id ? live! : base
                ImasMeishiPictureView(picture: s.picture, contentMode: .fit, fallback: Color.clear)
                    .frame(width: size.width * s.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        if selection == s.id {
                            Rectangle().strokeBorder(DS.ink, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .rotationEffect(.degrees(s.rotationDegrees))
                    .position(x: size.width * s.x, y: size.height * s.y)
                    .gesture(drag(base))
                    .onTapGesture { selection = base.id }
                    .accessibilityLabel("素材")
                    .accessibilityAddTraits(selection == base.id ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(width: size.width, height: size.height)
        .simultaneousGesture(pinchAndTwist)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func drag(_ base: ImasMeishiSticker) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart?.id != base.id {
                    dragStart = current(base.id) ?? base
                    selection = base.id
                }
                guard let start = dragStart else { return }
                live = moved(start, x: start.x + value.translation.width / size.width,
                             y: start.y + value.translation.height / size.height)
            }
            .onEnded { _ in commit() }
    }

    private var pinchAndTwist: some Gesture {
        SimultaneousGesture(MagnifyGesture(), RotateGesture())
            .onChanged { value in
                guard let id = selection, let base = stickers.first(where: { $0.id == id }) else { return }
                if dragStart?.id != id { dragStart = live?.id == id ? live! : base }
                guard let start = dragStart else { return }
                let scale = value.first?.magnification ?? 1
                let turn = value.second?.rotation.degrees ?? 0
                live = ImasMeishiSticker(id: start.id, picture: start.picture, x: start.x, y: start.y,
                                         width: start.width * scale, rotationDegrees: start.rotationDegrees + turn)
            }
            .onEnded { _ in commit() }
    }

    private func current(_ id: String) -> ImasMeishiSticker? {
        live?.id == id ? live : stickers.first { $0.id == id }
    }

    private func moved(_ s: ImasMeishiSticker, x: CGFloat, y: CGFloat) -> ImasMeishiSticker {
        ImasMeishiSticker(id: s.id, picture: s.picture, x: x, y: y, width: s.width, rotationDegrees: s.rotationDegrees)
    }

    private func commit() {
        if let live { onChange(live) }
        live = nil
        dragStart = nil
    }
}

extension View {
    /// 素材の見本・置く画面の名刺の枠 (内側の角丸で切る)。
    func imasStickerFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: DS.rInner, style: .continuous))
    }
}

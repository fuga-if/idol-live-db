import SwiftUI
import UIKit

/// 素材にする画像を整える (背景を切り抜くか選ぶ)。透過の PNG はそのまま使え、切り抜きは端末の中だけで行う
/// (`StickerCutout`)。決めたら PNG を渡す。
struct StickerPrepSheet: View {
    let image: UIImage
    let onUse: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cutout: UIImage?
    @State private var usesCutout = false
    @State private var isCutting = false
    @State private var notice: String?

    private var shown: UIImage { usesCutout ? (cutout ?? image) : image }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .padding(DS.Space.gap)
                        .background(ImasTransparencyBackdrop())
                        .imasStickerFrame()
                        .accessibilityLabel(usesCutout ? "背景を切り抜いた素材" : "素材")
                    ImasToggleRow(title: "背景を切り抜く",
                                  subtitle: "写っている人や物だけを残して、まわりを透明にします",
                                  isOn: Binding(get: { usesCutout }, set: { on in Task { await setCutout(on) } }))
                    if let notice {
                        Text(notice).imasText(.note, color: DS.ink)
                    }
                    Text("透明な部分のある画像 (PNG) はそのまま使えます。切り抜きは端末の中だけで行い、画像をどこにも送りません。")
                        .imasText(.note)
                }
            }
            .navigationTitle("素材を足す")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: !isCutting, onCancel: { dismiss() }, onSave: use))
            .imasSavingOverlay(isCutting, label: "切り抜いています")
        }
    }

    private func setCutout(_ on: Bool) async {
        notice = nil
        guard on else {
            usesCutout = false
            return
        }
        if cutout == nil {
            isCutting = true
            defer { isCutting = false }
            do {
                cutout = try await StickerCutout.cutout(image)
            } catch StickerCutout.Failure.noSubject {
                notice = "切り抜ける人や物が見つかりませんでした。写っているものがはっきりした画像で試してください。"
                return
            } catch {
                notice = "この端末では切り抜けませんでした。"
                return
            }
        }
        usesCutout = true
    }

    private func use() {
        guard let png = ProducerCardFiles.stickerPNG(shown) else {
            notice = "画像を用意できませんでした。"
            return
        }
        AppAnalytics.tap(usesCutout ? "producer_card.sticker.cutout" : "producer_card.sticker.add")
        onUse(png)
        dismiss()
    }
}

/// 名刺の上で素材を指で置く画面。名刺を画面の幅いっぱいに出し、引いて動かす・つまんで大きさ・2 本指で傾ける。
/// 選んだ素材は「いちばん上に」「外す」ができる。範囲・並びの規則はコア (`cardStickerClamp` など)。
struct StickerPlacementView: View {
    /// 素材を重ねない名刺 (見本)。
    let card: ImasProducerCard
    let images: [String: URL]
    @Binding var stickers: [CardSticker]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.gapLoose) {
                GeometryReader { geo in
                    let width = min(geo.size.width, ImasProducerCard.maxWidth)
                    let size = CGSize(width: width, height: width / ImasMeishi.aspect)
                    ZStack(alignment: .topLeading) {
                        card.frame(width: size.width)
                        ImasStickerEditLayer(stickers: views, selection: $selection, size: size) { moved in
                            let placed = CardSticker(id: moved.id, x: Double(moved.x), y: Double(moved.y),
                                                     width: Double(moved.width), rotationDegrees: moved.rotationDegrees)
                            stickers = cardStickersUpdate(stickers: stickers, sticker: placed)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    // 紙の外にはみ出した分は名刺でも切れるので、置くときも同じに見せる。
                    .imasStickerFrame()
                    .frame(maxWidth: .infinity)
                }
                .aspectRatio(ImasMeishi.aspect, contentMode: .fit)
                Text(selection == nil
                     ? "素材を押して選び、引いて動かします。2 本指でつまむと大きさ、ひねると傾きが変わります。"
                     : "2 本指でつまむと大きさ、ひねると傾きが変わります。何も無いところを押すと選び終わります。")
                    .imasText(.note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let selection {
                    HStack(spacing: DS.Space.gap) {
                        ImasButton(title: "いちばん上に", systemImage: "square.3.layers.3d.top.filled", role: .secondary) {
                            stickers = cardStickersBringToFront(stickers: stickers, id: selection)
                        }
                        ImasButton(title: "外す", systemImage: "trash", role: .destructive) {
                            stickers = cardStickersRemove(stickers: stickers, id: selection)
                            self.selection = nil
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.screen)
            .background(DS.bg)
            .navigationTitle("素材を置く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ImasToolbarButton(systemImage: "checkmark", label: "置き終える") { dismiss() }
                }
            }
        }
        .trackScreen("producer_card_sticker_place")
    }

    private var views: [ImasMeishiSticker] {
        stickers.compactMap { s in images[s.id].map { ProducerCardDisplay.stickerView(s, picture: .url($0)) } }
    }
}

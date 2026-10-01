import Nuke
import NukeUI
import SwiftUI

// =============================================================================
// ユニットのアバターと名札 (docs/DESIGN_SYSTEM.md §10.3・§6.6 相当)
//
// ImasUnitAvatar   ユニットの円形アイコン。カスタム画像があれば画像、無ければ所属ブランドの色
//                  (読めない間だけブランドキー由来の安定色) + person.3.fill のモノグラム。
// ImasUnitCell     ユニットの名札 (格子の 1 つ)。`ImasIdolCell` のユニット版。上の帯がブランド色。
// =============================================================================

struct ImasUnitAvatar: View {
    let unit: Unit
    var size: CGFloat = 36

    @Environment(\.colorScheme) private var scheme
    @State private var imageService = CustomImageService.shared

    var body: some View {
        let brandHex = BrandColors.hex(for: unit.brandId)
        let t = brandHex != nil
            ? ImasTheme.derive(seed: nil, brand: brandHex, scheme: scheme)
            : ImasTheme.derive(categoryKey: unit.brandId, scheme: scheme)
        core(t)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(t.ring, lineWidth: 1.5))
            .accessibilityLabel(unit.displayName)
    }

    @ViewBuilder private func core(_ t: ImasTheme) -> some View {
        if let imageURL = imageService.imageURL(for: unit.id, kind: .unit) {
            let px = Int(size * UIScreen.main.scale)
            ZStack {
                // 透過ロゴの下地。 .fit だと円の四隅が余るので、 敷かないと
                // リングの中に絵が浮いて見える。
                t.tint
                LazyImage(url: imageURL) { state in
                    if let img = state.image {
                        // ユニットアイコンは横長のロゴタイプが多い (SideM 等)。
                        // .fill だと左右が切れて何のユニットか判らなくなるので .fit で全体を収める。
                        // シャニの円形アイコンは 1:1 なのでほぼ余白なしで収まり、
                        // SideM の横長ロゴだけがひと回り小さく収まる。
                        img.resizable().scaledToFit().padding(size * 0.04)
                    } else {
                        fallback(t)
                    }
                }
                .processors([
                    ImageProcessors.Resize(
                        size: CGSize(width: px, height: px), unit: .pixels, contentMode: .aspectFit
                    )
                ])
            }
        } else {
            fallback(t)
        }
    }

    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            t.tint
            Image(systemName: "person.3.fill")
                .font(.imasDisplay(size * 0.42, weight: .semibold))
                .foregroundStyle(t.accent)
        }
    }
}

// MARK: - ユニットの名札 (格子)

/// ユニットの名札。`ImasIdolCell` のユニット版。上の帯がブランド色、その下にアイコンと名前。
/// 選ぶ格子 (ピッカー) では枠が点き、右上に選択の印。
struct ImasUnitCell: View {
    let unit: Unit
    /// 名札の下段に添える値 (「タグ 3 個一致」等)。nil なら出さない。
    var metric: String? = nil
    var isSelected: Bool? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let brandHex = BrandColors.hex(for: unit.brandId)
        let t = brandHex != nil
            ? ImasTheme.derive(seed: nil, brand: brandHex, scheme: scheme)
            : ImasTheme.derive(categoryKey: unit.brandId, scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            Rectangle().fill(t.accent).frame(height: 5)
            VStack(spacing: 4) {
                ImasUnitAvatar(unit: unit, size: 52)
                Text(unit.displayName).font(.imasHeading(12.5, weight: .heavy)).foregroundStyle(DS.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let metric {
                    Text(metric).font(.imasMono(10.5, weight: .semibold)).foregroundStyle(DS.ink3).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 7)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity)
        }
        .background(DS.surface, in: shape)
        .clipShape(shape)
        .overlay {
            if isSelected == true { shape.strokeBorder(t.accent, lineWidth: 2) }
        }
        .overlay(alignment: .topTrailing) {
            if let isSelected {
                ImasSelectionMark(isSelected: isSelected, brand: brandHex, size: 18)
                    .padding(.top, 9)
                    .padding(.trailing, 5)
            }
        }
        .imasSurfaceEdge(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([unit.displayName, metric].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}

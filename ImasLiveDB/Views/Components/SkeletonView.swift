import SwiftUI

// MARK: - Shimmer

/// 左→右に光沢を流すスケルトン用シマー。コンテナ全体に1回かけて使う (要素ごとに付けない)。
private struct ShimmerModifier: ViewModifier {
    @State private var x: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.13), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: x * geo.size.width)
                }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    x = 1.6
                }
            }
    }
}

extension View {
    /// スケルトン全体に光沢スイープを重ねる。
    func imasShimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Skeleton primitives

/// プレースホルダの角丸ブロック。
struct SkeletonBox: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DS.fill)
            .frame(width: width, height: height)
    }
}

private struct SkeletonCircle: View {
    var size: CGFloat
    var body: some View {
        Circle().fill(DS.fill).frame(width: size, height: size)
    }
}

// MARK: - List skeleton (ジャケ/アバター + テキスト2行)

/// 楽曲/イベント等のリスト用スケルトン。先頭サムネ形状を square/circle/none で切替。
struct ImasListSkeleton: View {
    enum Thumb { case square, circle, none }
    var rows: Int = 10
    var thumb: Thumb = .square

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: DS.sp3) {
                    switch thumb {
                    case .square: SkeletonBox(width: 44, height: 44, cornerRadius: 8)
                    case .circle: SkeletonCircle(size: 44)
                    case .none:   EmptyView()
                    }
                    VStack(alignment: .leading, spacing: DS.sp2) {
                        SkeletonBox(width: rowTitleWidth(i), height: 13)
                        SkeletonBox(width: rowSubWidth(i), height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp3)
                if i < rows - 1 {
                    Divider().overlay(DS.sep).padding(.leading, DS.sp5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .imasShimmer()
        .accessibilityHidden(true)
    }

    // 行ごとに幅を少し変えて単調さを消す (決定論的)。
    private func rowTitleWidth(_ i: Int) -> CGFloat { [180, 140, 210, 160, 120][i % 5] }
    private func rowSubWidth(_ i: Int) -> CGFloat { [90, 70, 110, 80, 60][i % 5] }
}

// MARK: - Grid skeleton (アバター円 + 名前)

/// アイドルグリッド用スケルトン。
struct ImasGridSkeleton: View {
    var columns: Int = 4
    var count: Int = 16
    var avatarSize: CGFloat = 60

    private var grid: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: grid, spacing: DS.sp5) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(spacing: DS.sp2) {
                    SkeletonCircle(size: avatarSize)
                    SkeletonBox(width: 48, height: 10)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DS.sp4)
        .padding(.top, DS.sp4)
        .frame(maxWidth: .infinity, alignment: .top)
        .imasShimmer()
        .accessibilityHidden(true)
    }
}

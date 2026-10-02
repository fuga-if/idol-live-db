import SwiftUI

// MARK: - Shimmer

/// スケルトンの読み込み中の印。光沢を流さず (ぼんやり光る表現は使わない)、塗りの濃さを静かに上下させる。
private struct ShimmerModifier: ViewModifier {
    @State private var dim = false
    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

extension View {
    /// スケルトン全体の濃さを静かに上下させる。
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
                    ImasRowDivider(inset: DS.sp5)
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

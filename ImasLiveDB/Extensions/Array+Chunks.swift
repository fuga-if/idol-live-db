import Foundation

extension Array {
    /// 配列を指定サイズのチャンクに分割する。
    func chunks(ofCount size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

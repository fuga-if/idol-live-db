import Foundation

extension ProcessInfo {
    /// XCTest のテストホストとして起動されているか。
    /// `XCTestConfigurationFilePath` は xcodebuild test が必ず入れる。
    ///
    /// テストホストは本物のアプリなので、何もしないと起動時の副作用 (CloudKit 同期・
    /// 認証の更新・通知の再登録・ウィジェットへの書き出し・更新確認・計測の初期化) が
    /// テスト中にも走り、テストを不安定にしたうえネットワークにも出る。
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

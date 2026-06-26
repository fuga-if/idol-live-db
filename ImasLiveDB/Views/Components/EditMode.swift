import Foundation

/// マスタ編集 View (EventEditView / ShowEditView / IdolEditView / SongEditView 等) が
/// 「既存修正」か「新規作成」かを区別するためのモード。
///
/// - `.update(original)`: 既存レコードを編集。recordName は既知、op=update で送る。
/// - `.create`: 新規作成。recordName はサーバ採番なので省略し、op=create で送る。
///   レスポンスの確定 ID でローカル upsert する。
enum EditMode<Model> {
    case update(original: Model)
    case create

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }

    /// 既存編集時の元レコード (新規作成時は nil)。
    var original: Model? {
        if case .update(let original) = self { return original }
        return nil
    }
}

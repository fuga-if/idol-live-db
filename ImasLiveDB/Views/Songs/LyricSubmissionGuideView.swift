import SwiftUI

/// 歌詞の投稿ガイドライン (読みもの)。中身はコア (`lyricSubmissionGuideline`) が持ち、ここは並べるだけ。
struct LyricSubmissionGuideView: View {
    var body: some View {
        ImasPage {
            ImasProse(blocks: lyricSubmissionGuideline().map { block in
                switch block {
                case .heading(let text): return .heading(text)
                case .paragraph(let text): return .paragraph(text)
                case .bullets(let items): return .bullets(items)
                case .note(let text): return .note(text)
                }
            })
        }
        .navigationTitle("投稿ガイドライン")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("lyric_submission_guide")
    }
}

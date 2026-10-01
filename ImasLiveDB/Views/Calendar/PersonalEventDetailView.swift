import SwiftUI

/// 端末カレンダー由来のマイ予定の簡易詳細シート (表示のみ・編集不可)。
/// タイトル / 日時範囲 / カレンダー名 / 場所 (あれば) を medium detent で表示する。
struct PersonalEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: PersonalCalendarEvent

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                infoRows
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.bg)
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .trackScreen("personal_event")
        }
    }

    /// マイ予定はカレンダーの色をそのまま使う (DB 由来の実体色ではないため)。
    private var eventColorHex: String { ColorMath.hexString(from: event.color) }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            ImasLeadBar(seed: eventColorHex)
                .frame(height: 44)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(event.title)
                    .font(.imasTitle3.weight(.bold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(3)
                Text("マイ予定")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.sp6)
        .padding(.top, DS.sp6)
        .padding(.bottom, DS.sp4)
        .background(DS.surface)
    }

    // MARK: - 情報行

    private var infoRows: some View {
        ImasCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                infoRow(systemImage: "clock", title: "日時", value: dateRangeText)
                ImasRowDivider(inset: 48)
                infoRow(systemImage: "calendar", title: "カレンダー", value: event.calendarTitle)
                if let location = event.location {
                    ImasRowDivider(inset: 48)
                    infoRow(systemImage: "mappin.and.ellipse", title: "場所", value: location)
                }
            }
            .padding(.vertical, DS.sp2)
        }
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp4)
    }

    private func infoRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp3) {
            ImasIconTile(systemImage: systemImage, size: .s28, tone: .themed, seed: eventColorHex)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(title)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                Text(value)
                    .font(.imasSubhead.weight(.medium))
                    .foregroundStyle(DS.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
    }

    // MARK: - 日時テキスト

    private var dateRangeText: String {
        let cal = Calendar.current
        if event.isAllDay {
            // EKEvent の終日予定は end が翌日 0:00 になることがあるため 1 秒戻して最終日を求める
            let lastDay = max(event.start, event.end.addingTimeInterval(-1))
            if cal.isDate(event.start, inSameDayAs: lastDay) {
                return "\(event.start.formatted(.dateTime.year().month().day().weekday(.short))) 終日"
            }
            return "\(event.start.formatted(.dateTime.month().day())) 〜 \(lastDay.formatted(.dateTime.month().day())) 終日"
        }
        if cal.isDate(event.start, inSameDayAs: event.end) {
            let day = event.start.formatted(.dateTime.year().month().day().weekday(.short))
            let startTime = event.start.formatted(date: .omitted, time: .shortened)
            let endTime = event.end.formatted(date: .omitted, time: .shortened)
            return "\(day) \(startTime) 〜 \(endTime)"
        }
        let startText = event.start.formatted(.dateTime.month().day().hour().minute())
        let endText = event.end.formatted(.dateTime.month().day().hour().minute())
        return "\(startText) 〜 \(endText)"
    }
}

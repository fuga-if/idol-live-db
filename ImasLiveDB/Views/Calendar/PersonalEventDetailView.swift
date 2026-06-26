import SwiftUI

/// 端末カレンダー由来のマイ予定の簡易詳細シート (表示のみ・編集不可)。
/// タイトル / 日時範囲 / カレンダー名 / 場所 (あれば) を medium detent で表示する。
struct PersonalEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: PersonalCalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            infoRows
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.bg)
        .trackScreen("personal_event")
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.color)
                .frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.imasTitle3.weight(.bold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(3)
                Text("マイ予定")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
            }
            Spacer(minLength: DS.sp2)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.imasScaled( 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, DS.sp6)
        .padding(.top, DS.sp6)
        .padding(.bottom, DS.sp4)
        .background(DS.surface)
    }

    // MARK: - 情報行

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoRow(systemImage: "clock", title: "日時", value: dateRangeText)
            Divider().overlay(DS.sep).padding(.leading, 48)
            infoRow(systemImage: "calendar", title: "カレンダー", value: event.calendarTitle)
            if let location = event.location {
                Divider().overlay(DS.sep).padding(.leading, 48)
                infoRow(systemImage: "mappin.and.ellipse", title: "場所", value: location)
            }
        }
        .padding(.vertical, DS.sp2)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp4)
    }

    private func infoRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp3) {
            Image(systemName: systemImage)
                .font(.imasScaled( 15, weight: .semibold))
                .foregroundStyle(event.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
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

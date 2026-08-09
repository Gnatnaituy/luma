import Foundation
import Testing

@testable import Luma

@Suite
struct CalendarTests {
    @Test
    func calendarGridAndLunarData() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let newYear = try #require(formatter.date(from: "2026-02-17"))
        let makeUpWorkday = try #require(formatter.date(from: "2026-02-14"))
        let startOfAutumn = try #require(formatter.date(from: "2026-08-07"))

        try expect(LumaCalendarData.lunarText(for: newYear) == "正月", "Chinese New Year has the expected lunar month label")
        try expect(LumaCalendarData.festival(for: newYear) == "春节", "Chinese New Year is marked as a festival")
        try expect(LumaCalendarData.solarTerm(for: startOfAutumn) == "立秋", "the solar term for August 7, 2026 is Start of Autumn")
        try expect(
            LumaCalendarData.holidayInfo(for: newYear) == LumaCalendarHoliday(name: "春节", kind: .holiday),
            "official holiday schedule marks Chinese New Year as a holiday"
        )
        try expect(
            LumaCalendarData.holidayInfo(for: makeUpWorkday) == LumaCalendarHoliday(name: "春节调休", kind: .workday),
            "official holiday schedule marks the make-up workday"
        )
        try expect(LumaCalendarData.fullDateText(for: makeUpWorkday).hasSuffix("星期六"), "weekday mapping remains localized")

        let month = LumaCalendarData.monthDays(containing: newYear, today: newYear)
        try expect(month.count % 7 == 0 && month.contains(where: { $0.isToday }), "month grid is complete and marks today")
        try expect(
            month.first(where: { $0.isInDisplayedMonth })?.dayNumber == 1,
            "February 2026 contains the first day in its displayed month"
        )

        let autumnMonth = LumaCalendarData.monthDays(containing: startOfAutumn, today: startOfAutumn)
        try expect(
            autumnMonth.first(where: { $0.date == LumaCalendarData.startOfDay(startOfAutumn) })?.solarTerm == "立秋",
            "month grid exposes the solar term marker"
        )
        try expect(
            LumaCalendarData.yearTitle(for: LumaCalendarData.addingYears(1, to: newYear)) == "2027年"
                && LumaCalendarData.monthTitle(for: LumaCalendarData.date(year: 2027, month: 8)!) == "2027年8月",
            "year navigation preserves the selected month while changing the year"
        )
    }

    private func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw TestFailure(name) }
    }
}

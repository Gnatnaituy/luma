import Foundation

enum LumaCalendarHolidayKind: Equatable {
    case holiday
    case workday
}

struct LumaCalendarHoliday: Equatable {
    let name: String
    let kind: LumaCalendarHolidayKind
}

struct LumaCalendarDay: Identifiable, Equatable {
    let date: Date
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isWeekend: Bool
    let lunarText: String
    let festival: String?
    let solarTerm: String?
    let holiday: LumaCalendarHoliday?

    var id: Date { date }

    var label: String? {
        if let holiday, holiday.kind == .workday { return L10n.text("班", "Work") }
        return (holiday?.name ?? festival).map(LumaCalendarData.localizedName)
    }

    var marker: String? {
        solarTerm.map(LumaCalendarData.localizedName) ?? label
    }
}

enum LumaCalendarData {
    private static let solarCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }()

    private static let lunarCalendar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        return calendar
    }()

    private static let lunarMonthNames = [
        "正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"
    ]

    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    private static let solarFestivalNames: [String: String] = [
        "01-01": "元旦",
        "02-14": "情人节",
        "03-08": "妇女节",
        "04-01": "愚人节",
        "05-01": "劳动节",
        "06-01": "儿童节",
        "07-01": "建党节",
        "08-01": "建军节",
        "09-10": "教师节",
        "10-01": "国庆节",
        "12-24": "平安夜",
        "12-25": "圣诞节"
    ]

    private static let solarTermNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    // Dates for the current and previous year are pinned so the displayed result is
    // stable. Other years use the standard 21st-century solar-term day formula.
    private static let pinnedSolarTermDays: [Int: [Int]] = [
        2025: [5, 20, 3, 18, 5, 20, 4, 20, 5, 21, 5, 21, 7, 22, 7, 23, 7, 23, 8, 23, 7, 22, 7, 21],
        2026: [5, 20, 4, 19, 5, 20, 5, 20, 5, 21, 5, 21, 7, 23, 7, 23, 7, 23, 8, 23, 7, 22, 7, 22]
    ]

    private static let solarTermCoefficients = [
        5.4055, 20.12, 3.87, 18.73, 5.63, 20.646, 4.81, 20.1,
        5.52, 21.04, 5.678, 21.37, 7.108, 22.83, 7.5, 23.13,
        7.646, 23.042, 8.318, 23.438, 7.438, 22.36, 7.18, 22.6
    ]

    // The statutory holiday and make-up workday dates are intentionally local and read-only.
    // They are maintained from the State Council holiday notices; unscheduled years still
    // show weekends and traditional festivals without pretending to know adjustment days.
    private static let officialSchedule: [String: LumaCalendarHoliday] = {
        var schedule: [String: LumaCalendarHoliday] = [:]

        func add(_ dates: [String], name: String, kind: LumaCalendarHolidayKind) {
            for date in dates { schedule[date] = LumaCalendarHoliday(name: name, kind: kind) }
        }

        add(["2025-01-01"], name: "元旦", kind: .holiday)
        add(dates(from: "2025-01-28", to: "2025-02-04"), name: "春节", kind: .holiday)
        add(["2025-01-26", "2025-02-08"], name: "春节调休", kind: .workday)
        add(dates(from: "2025-04-04", to: "2025-04-06"), name: "清明节", kind: .holiday)
        add(dates(from: "2025-05-01", to: "2025-05-05"), name: "劳动节", kind: .holiday)
        add(["2025-04-27"], name: "劳动节调休", kind: .workday)
        add(dates(from: "2025-05-31", to: "2025-06-02"), name: "端午节", kind: .holiday)
        add(dates(from: "2025-10-01", to: "2025-10-08"), name: "国庆节、中秋节", kind: .holiday)
        add(["2025-09-28", "2025-10-11"], name: "国庆节调休", kind: .workday)

        add(dates(from: "2026-01-01", to: "2026-01-03"), name: "元旦", kind: .holiday)
        add(["2026-01-04"], name: "元旦调休", kind: .workday)
        add(dates(from: "2026-02-15", to: "2026-02-23"), name: "春节", kind: .holiday)
        add(["2026-02-14", "2026-02-28"], name: "春节调休", kind: .workday)
        add(dates(from: "2026-04-04", to: "2026-04-06"), name: "清明节", kind: .holiday)
        add(dates(from: "2026-05-01", to: "2026-05-05"), name: "劳动节", kind: .holiday)
        add(["2026-05-09"], name: "劳动节调休", kind: .workday)
        add(dates(from: "2026-06-19", to: "2026-06-21"), name: "端午节", kind: .holiday)
        add(dates(from: "2026-09-25", to: "2026-09-27"), name: "中秋节", kind: .holiday)
        add(dates(from: "2026-10-01", to: "2026-10-07"), name: "国庆节", kind: .holiday)
        add(["2026-09-20", "2026-10-10"], name: "国庆节调休", kind: .workday)

        return schedule
    }()

    static var weekdaySymbols: [String] {
        L10n.language == .english
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["一", "二", "三", "四", "五", "六", "日"]
    }

    static func startOfDay(_ date: Date) -> Date {
        solarCalendar.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let components = solarCalendar.dateComponents([.year, .month], from: date)
        return solarCalendar.date(from: DateComponents(year: components.year, month: components.month, day: 1))
            ?? solarCalendar.startOfDay(for: date)
    }

    static func startOfYear(_ date: Date) -> Date {
        let components = solarCalendar.dateComponents([.year], from: date)
        return solarCalendar.date(from: DateComponents(year: components.year, month: 1, day: 1))
            ?? solarCalendar.startOfDay(for: date)
    }

    static func addingMonths(_ value: Int, to date: Date) -> Date {
        solarCalendar.date(byAdding: .month, value: value, to: startOfMonth(date)) ?? date
    }

    static func addingYears(_ value: Int, to date: Date) -> Date {
        solarCalendar.date(byAdding: .year, value: value, to: startOfYear(date)) ?? date
    }

    static func date(year: Int, month: Int) -> Date? {
        solarCalendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    static func monthTitle(for date: Date) -> String {
        if L10n.language == .english {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        let components = solarCalendar.dateComponents([.year, .month], from: date)
        return String(components.year ?? 0) + "年" + String(components.month ?? 0) + "月"
    }

    static func yearTitle(for date: Date) -> String {
        let year = String(solarCalendar.component(.year, from: date))
        return L10n.language == .english ? year : year + "年"
    }

    static func fullDateText(for date: Date) -> String {
        if L10n.language == .english {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateStyle = .full
            return formatter.string(from: date)
        }
        let components = solarCalendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekday = components.weekday.flatMap { weekdaySymbols[safe: $0 == 1 ? 6 : $0 - 2] } ?? ""
        return String(components.year ?? 0) + "年"
            + String(components.month ?? 0) + "月"
            + String(components.day ?? 0) + "日 星期" + weekday
    }

    static func monthDays(containing date: Date, today: Date = Date()) -> [LumaCalendarDay] {
        let month = startOfMonth(date)
        let components = solarCalendar.dateComponents([.year, .month], from: month)
        let monthStart = solarCalendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? month
        let dayRange = solarCalendar.range(of: .day, in: .month, for: monthStart) ?? 1..<32
        let leadingDays = (solarCalendar.component(.weekday, from: monthStart) - solarCalendar.firstWeekday + 7) % 7
        let cellCount = leadingDays + dayRange.count
        let trailingDays = (7 - cellCount % 7) % 7
        let totalDays = cellCount + trailingDays
        let normalizedToday = startOfDay(today)

        return (0..<totalDays).compactMap { index in
            guard let cellDate = solarCalendar.date(byAdding: .day, value: index - leadingDays, to: monthStart) else {
                return nil
            }
            let cellComponents = solarCalendar.dateComponents([.year, .month, .day, .weekday], from: cellDate)
            let isInMonth = cellComponents.month == components.month && cellComponents.year == components.year
            return LumaCalendarDay(
                date: startOfDay(cellDate),
                dayNumber: cellComponents.day ?? 0,
                isInDisplayedMonth: isInMonth,
                isToday: startOfDay(cellDate) == normalizedToday,
                isWeekend: cellComponents.weekday == 1 || cellComponents.weekday == 7,
                lunarText: lunarText(for: cellDate),
                festival: festival(for: cellDate),
                solarTerm: solarTerm(for: cellDate),
                holiday: holidayInfo(for: cellDate)
            )
        }
    }

    static func lunarText(for date: Date) -> String {
        let components = lunarCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = components.month, let day = components.day,
              lunarMonthNames.indices.contains(month - 1), lunarDayNames.indices.contains(day - 1)
        else { return "" }

        if L10n.language == .english {
            return "L\(month)/\(day)"
        }

        if day == 1 {
            let prefix = components.isLeapMonth == true ? "闰" : ""
            return prefix + lunarMonthNames[month - 1] + "月"
        }
        return lunarDayNames[day - 1]
    }

    static func festival(for date: Date) -> String? {
        let solarComponents = solarCalendar.dateComponents([.month, .day], from: date)
        if let month = solarComponents.month, let day = solarComponents.day,
           let festival = solarFestivalNames[String(format: "%02d-%02d", month, day)] {
            return festival
        }

        let lunarComponents = lunarCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard lunarComponents.isLeapMonth != true,
              let month = lunarComponents.month,
              let day = lunarComponents.day else { return nil }
        switch (month, day) {
        case (1, 1): return "春节"
        case (1, 15): return "元宵节"
        case (5, 5): return "端午节"
        case (7, 7): return "七夕"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        case (12, 8): return "腊八节"
        case (12, 23), (12, 24): return "小年"
        case (12, 29), (12, 30): return "除夕"
        default: return nil
        }
    }

    static func solarTerm(for date: Date) -> String? {
        let components = solarCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }

        for index in solarTermNames.indices where solarTermMonth(for: index) == month {
            guard let termDay = solarTermDay(year: year, index: index) else { continue }
            if termDay == day { return solarTermNames[index] }
        }
        return nil
    }

    static func holidayInfo(for date: Date) -> LumaCalendarHoliday? {
        officialSchedule[dateKey(for: date)]
    }

    static func localizedName(_ value: String) -> String {
        guard L10n.language == .english else { return value }
        return englishNames[value] ?? value
    }

    private static let englishNames: [String: String] = [
        "元旦": "New Year's Day",
        "情人节": "Valentine's Day",
        "妇女节": "Women's Day",
        "愚人节": "April Fools' Day",
        "劳动节": "Labor Day",
        "儿童节": "Children's Day",
        "建党节": "CPC Founding Day",
        "建军节": "Army Day",
        "教师节": "Teachers' Day",
        "国庆节": "National Day",
        "平安夜": "Christmas Eve",
        "圣诞节": "Christmas Day",
        "春节": "Spring Festival",
        "元宵节": "Lantern Festival",
        "端午节": "Dragon Boat Festival",
        "七夕": "Qixi Festival",
        "中秋节": "Mid-Autumn Festival",
        "重阳节": "Double Ninth Festival",
        "腊八节": "Laba Festival",
        "小年": "Little New Year",
        "除夕": "Lunar New Year's Eve",
        "清明节": "Qingming Festival",
        "春节调休": "Spring Festival Workday",
        "元旦调休": "New Year Workday",
        "劳动节调休": "Labor Day Workday",
        "国庆节调休": "National Day Workday",
        "国庆节、中秋节": "National Day & Mid-Autumn Festival",
        "小寒": "Minor Cold",
        "大寒": "Major Cold",
        "立春": "Start of Spring",
        "雨水": "Rain Water",
        "惊蛰": "Awakening of Insects",
        "春分": "Spring Equinox",
        "清明": "Clear and Bright",
        "谷雨": "Grain Rain",
        "立夏": "Start of Summer",
        "小满": "Grain Full",
        "芒种": "Grain in Ear",
        "夏至": "Summer Solstice",
        "小暑": "Minor Heat",
        "大暑": "Major Heat",
        "立秋": "Start of Autumn",
        "处暑": "End of Heat",
        "白露": "White Dew",
        "秋分": "Autumn Equinox",
        "寒露": "Cold Dew",
        "霜降": "Frost's Descent",
        "立冬": "Start of Winter",
        "小雪": "Minor Snow",
        "大雪": "Major Snow",
        "冬至": "Winter Solstice"
    ]

    private static func dateKey(for date: Date) -> String {
        let components = solarCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func solarTermMonth(for index: Int) -> Int {
        index / 2 + 1
    }

    private static func solarTermDay(year: Int, index: Int) -> Int? {
        if let pinnedDays = pinnedSolarTermDays[year], pinnedDays.indices.contains(index) {
            return pinnedDays[index]
        }
        guard year >= 2000, year <= 2099, solarTermCoefficients.indices.contains(index) else { return nil }

        let yearInCentury = year % 100
        let leapCorrection = (yearInCentury - 1) / 4
        return Int(floor(Double(yearInCentury) * 0.2422 + solarTermCoefficients[index])) - leapCorrection
    }

    private static func dates(from start: String, to end: String) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = solarCalendar
        formatter.dateFormat = "yyyy-MM-dd"
        guard let startDate = formatter.date(from: start), let endDate = formatter.date(from: end) else { return [] }

        var values: [String] = []
        var date = startDate
        while date <= endDate {
            values.append(formatter.string(from: date))
            guard let next = solarCalendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return values
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

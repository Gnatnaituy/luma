import SwiftUI

private enum LumaCalendarViewMode: String, CaseIterable {
    case month
    case year

    var title: String {
        switch self {
        case .month: L10n.text("月", "Month")
        case .year: L10n.text("年", "Year")
        }
    }
}

struct CalendarPluginView: View {
    @State private var displayedMonth = LumaCalendarData.startOfMonth(Date())
    @State private var selectedDate = LumaCalendarData.startOfDay(Date())
    @State private var viewMode: LumaCalendarViewMode = .month

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let yearColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var days: [LumaCalendarDay] {
        LumaCalendarData.monthDays(containing: displayedMonth)
    }

    private var selectedDay: LumaCalendarDay {
        if let day = days.first(where: { $0.date == selectedDate }) { return day }
        let fallbackDate = LumaCalendarData.startOfDay(selectedDate)
        return LumaCalendarData.monthDays(containing: fallbackDate).first(where: { $0.date == fallbackDate })
            ?? days.first!
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HStack(alignment: .top, spacing: 0) {
                ZStack {
                    if viewMode == .month {
                        calendarGrid
                            .transition(LumaMotion.contentTransition)
                    } else {
                        yearGrid
                            .transition(LumaMotion.contentTransition)
                    }
                }
                    .id(viewMode.rawValue)
                    .frame(maxWidth: .infinity)
                    .animation(LumaMotion.standard, value: viewMode)

                Divider()
                    .padding(.vertical, 4)

                selectedDaySummary
                    .frame(width: 228)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            let today = LumaCalendarData.startOfDay(Date())
            selectedDate = today
            displayedMonth = LumaCalendarData.startOfMonth(today)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewMode == .month
                    ? LumaCalendarData.monthTitle(for: displayedMonth)
                    : LumaCalendarData.yearTitle(for: displayedMonth))
                    .font(.title2.weight(.bold))
                Text(L10n.text(
                    "公历 · 农历 · 节气 · 节假日",
                    "Solar · Lunar · Solar Terms · Holidays"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $viewMode) {
                ForEach(LumaCalendarViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 86)
            .help(L10n.text("切换月视图或年视图", "Switch between month and year views"))

            Button {
                let today = LumaCalendarData.startOfDay(Date())
                displayedMonth = LumaCalendarData.startOfMonth(today)
                selectedDate = today
            } label: {
                Text(L10n.text("今天", "Today"))
            }
            .buttonStyle(LumaTextButtonStyle(emphasis: .primary, height: 30))

            Button {
                displayedMonth = viewMode == .month
                    ? LumaCalendarData.addingMonths(-1, to: displayedMonth)
                    : LumaCalendarData.addingYears(-1, to: displayedMonth)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(LumaIconButtonStyle(size: 30))
            .help(viewMode == .month
                ? L10n.text("上个月", "Previous Month")
                : L10n.text("上一年", "Previous Year"))

            Button {
                displayedMonth = viewMode == .month
                    ? LumaCalendarData.addingMonths(1, to: displayedMonth)
                    : LumaCalendarData.addingYears(1, to: displayedMonth)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(LumaIconButtonStyle(size: 30))
            .help(viewMode == .month
                ? L10n.text("下个月", "Next Month")
                : L10n.text("下一年", "Next Year"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(LumaMotion.quick, value: viewMode)
        .animation(LumaMotion.standard, value: displayedMonth)
    }

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(LumaCalendarData.weekdaySymbols.enumerated()), id: \.offset) { index, weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(index >= 5 ? .orange : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(days) { day in
                    LumaCalendarDayCell(
                        day: day,
                        isSelected: day.date == selectedDate
                    ) {
                        selectedDate = day.date
                        if !day.isInDisplayedMonth {
                            displayedMonth = LumaCalendarData.startOfMonth(day.date)
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                legend(color: .accentColor, title: L10n.text("今天", "Today"))
                legend(color: .green, title: L10n.text("节气", "Solar Term"))
                legend(color: .red, title: L10n.text("节假日", "Holiday"))
                legend(color: .orange, title: L10n.text("调休上班", "Make-up Workday"))
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private var yearGrid: some View {
        ScrollView {
            LazyVGrid(columns: yearColumns, spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    if let monthDate = LumaCalendarData.date(
                        year: Calendar.current.component(.year, from: displayedMonth),
                        month: month
                    ) {
                        LumaCalendarYearMonthCard(
                            monthDate: monthDate,
                            selectedDate: selectedDate,
                            today: LumaCalendarData.startOfDay(Date())
                        ) { date in
                            selectedDate = date
                        }
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
    }

    private var selectedDaySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("日期详情", "Date Details"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(selectedDay.dayNumber)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedDay.isWeekend ? .orange : .primary)
                Text(LumaCalendarData.fullDateText(for: selectedDay.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            detailRow(
                icon: "moon.stars.fill",
                title: L10n.text("农历", "Lunar"),
                value: selectedDay.lunarText,
                color: .indigo
            )

            if let solarTerm = selectedDay.solarTerm {
                detailRow(
                    icon: "sun.max.fill",
                    title: L10n.text("节气", "Solar Term"),
                    value: LumaCalendarData.localizedName(solarTerm),
                    color: .green
                )
            }

            if let label = selectedDay.label {
                detailRow(
                    icon: selectedDay.holiday?.kind == .workday ? "briefcase.fill" : "flag.fill",
                    title: selectedDay.holiday?.kind == .workday
                        ? L10n.text("工作安排", "Work Schedule")
                        : L10n.text("节日", "Festival"),
                    value: selectedDay.holiday?.kind == .workday
                        ? LumaCalendarData.localizedName(selectedDay.holiday?.name ?? label)
                        : label,
                    color: selectedDay.holiday?.kind == .workday ? .orange : .red
                )
            } else {
                detailRow(
                    icon: "calendar",
                    title: L10n.text("节假日", "Holiday"),
                    value: L10n.text("无特别标记", "No special designation"),
                    color: .secondary
                )
            }

            Spacer(minLength: 4)
        }
        .padding(.leading, 18)
        .padding(.top, 2)
        .animation(LumaMotion.quick, value: selectedDate)
    }

    private func detailRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
            }
        }
    }
}

private struct LumaCalendarYearMonthCard: View {
    let monthDate: Date
    let selectedDate: Date
    let today: Date
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    private var days: [LumaCalendarDay] {
        LumaCalendarData.monthDays(containing: monthDate, today: today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LumaCalendarData.monthTitle(for: monthDate))
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.leading, 3)

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(LumaCalendarData.weekdaySymbols.enumerated()), id: \.offset) { index, weekday in
                    Text(weekday)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(index >= 5 ? .orange : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 13)
                }

                ForEach(days) { day in
                    Button {
                        onSelect(day.date)
                    } label: {
                        LumaCalendarYearDayCell(
                            day: day,
                            isSelected: day.date == selectedDate
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!day.isInDisplayedMonth)
                }
            }
        }
        .padding(7)
        .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LumaCalendarYearDayCell: View {
    let day: LumaCalendarDay
    let isSelected: Bool

    private var numberColor: Color {
        if !day.isInDisplayedMonth { return .gray.opacity(0.55) }
        if day.holiday?.kind == .holiday || day.festival != nil { return .red }
        if day.isWeekend { return .orange }
        return .primary
    }

    private var markerColor: Color {
        if day.solarTerm != nil { return .green }
        if day.holiday?.kind == .workday { return .orange }
        return .red
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)

            Text("\(day.dayNumber)")
                .font(.system(size: 10, weight: day.isToday ? .bold : .regular, design: .rounded))
                .foregroundStyle(numberColor)

            if day.marker != nil {
                Circle()
                    .fill(markerColor)
                    .frame(width: 3, height: 3)
                    .offset(y: -1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 17)
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
    }
}

private struct LumaCalendarDayCell: View {
    let day: LumaCalendarDay
    let isSelected: Bool
    let action: () -> Void

    private var numberColor: Color {
        if !day.isInDisplayedMonth { return .secondary }
        if day.holiday?.kind == .holiday || day.festival != nil { return .red }
        if day.isWeekend { return .orange }
        return .primary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 3) {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 16, weight: day.isToday ? .bold : .medium, design: .rounded))
                        .foregroundStyle(numberColor)
                    Spacer(minLength: 0)
                    if day.isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }
                }

                Text(day.lunarText)
                    .font(.system(size: 10))
                    .foregroundStyle(day.isInDisplayedMonth ? .secondary : .tertiary)
                    .lineLimit(1)

                Text(day.marker ?? " ")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(
                        day.solarTerm != nil
                            ? .green
                            : (day.holiday?.kind == .workday ? .orange : .red)
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(
                isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(day.isInDisplayedMonth ? 0.028 : 0.012),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                }
            }
            .opacity(day.isInDisplayedMonth ? 1 : 0.48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .animation(LumaMotion.quick, value: isSelected)
    }

    private var accessibilityLabel: String {
        var values = [
            L10n.text("\(day.dayNumber)日", "Day \(day.dayNumber)"),
            day.lunarText
        ]
        if let label = day.label { values.append(label) }
        if day.isToday { values.append(L10n.text("今天", "Today")) }
        return values.joined(separator: L10n.text("，", ", "))
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct WeatherPluginView: View {
    @ObservedObject var store: WeatherStore
    @State private var query = ""
    @State private var suggestions: [WeatherLocation] = []
    @State private var selectedSuggestionID: Int?
    @State private var draggingLocationID: Int?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    TextField("上海 / Tokyo / 10001", text: $query)
                        .textFieldStyle(LumaTextFieldStyle())
                        .focused($isQueryFocused)
                        .onSubmit(performQuery)
                        .onMoveCommand(perform: performSuggestionMove)

                    Button(action: performQuery) {
                        if store.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .disabled(store.isBusy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("添加地点")

                    if !store.records.isEmpty {
                        Button { Task { await store.refreshAll() } } label: {
                            if store.isRefreshingAll { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.clockwise") }
                        }
                        .buttonStyle(LumaIconButtonStyle())
                        .disabled(store.isBusy)
                        .help(store.isRefreshingAll ? "正在全部刷新" : "全部刷新")
                    }
                }
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if isQueryFocused, !suggestions.isEmpty {
                        weatherSuggestionPanel
                            .padding(.horizontal, 12)
                            .offset(y: 48)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .zIndex(20)

                if !store.errorMessage.isEmpty {
                    Text(store.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if store.records.isEmpty {
                    ContentUnavailableView(
                        "添加地点",
                        systemImage: "location.badge.plus",
                        description: Text("输入城市、地区或邮政编码")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.records) { snapshot in
                                WindowDragExclusion {
                                    WeatherListRow(snapshot: snapshot)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                        .background(
                                            store.selectedLocationID == snapshot.id
                                                ? Color.accentColor.opacity(0.14)
                                                : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .onTapGesture {
                                            store.select(snapshot)
                                        }
                                        .onDrag {
                                            draggingLocationID = snapshot.id
                                            return NSItemProvider(object: NSString(string: String(snapshot.id)))
                                        }
                                        .onDrop(
                                            of: [UTType.text],
                                            delegate: WeatherRowDropDelegate(
                                                targetID: snapshot.id,
                                                draggingID: $draggingLocationID,
                                                move: { source, target in
                                                    store.move(source, before: target)
                                                }
                                            )
                                        )
                                        .contextMenu {
                                            Button("移除地点", role: .destructive) { store.remove(snapshot) }
                                        }
                                        .accessibilityAddTraits(.isButton)
                                }
                                .lumaContentTransition()
                            }
                        }
                        .padding(.horizontal, 6)
                        .animation(LumaMotion.standard, value: store.records.map(\.id))
                    }
                }
            }
            .frame(width: 218)
            .background(Color.primary.opacity(0.025))

            Divider()

            ZStack(alignment: .topLeading) {
                if let snapshot = store.selected {
                    WeatherDetailView(snapshot: snapshot, dataSource: store.dataSource, isLoading: store.isBusy) {
                        Task { await store.refreshSelected() }
                    }
                    .id(snapshot.id)
                    .lumaContentTransition()
                } else {
                    ContentUnavailableView(
                        "还没有天气记录",
                        systemImage: "cloud.sun",
                        description: Text("从左侧添加一个地点开始")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .lumaContentTransition()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(LumaMotion.quick, value: store.selectedLocationID)
        }
        .onAppear { DispatchQueue.main.async { isQueryFocused = true } }
        .task(id: query) { await updateSuggestions() }
    }

    private func performQuery() {
        if let selected = suggestions.first(where: { $0.id == selectedSuggestionID }) ?? suggestions.first {
            add(selected)
            return
        }
        let value = query
        Task {
            await store.add(value)
            if store.errorMessage.isEmpty { query = "" }
        }
    }

    private var weatherSuggestionPanel: some View {
        VStack(spacing: 2) {
            ForEach(suggestions) { location in
                Button { add(location) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.blue)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(location.subtitle.isEmpty ? location.timezone : location.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        selectedSuggestionID == location.id ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12)))
        .animation(LumaMotion.quick, value: suggestions.map(\.id))
    }

    private func updateSuggestions() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else {
            suggestions = []
            selectedSuggestionID = nil
            return
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        do {
            let results = try await OpenMeteoWeatherService().searchLocations(value)
            guard !Task.isCancelled else { return }
            suggestions = results
            selectedSuggestionID = results.first?.id
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            selectedSuggestionID = nil
        }
    }

    private func performSuggestionMove(_ direction: MoveCommandDirection) {
        guard !suggestions.isEmpty, direction == .up || direction == .down else { return }
        let current = suggestions.firstIndex { $0.id == selectedSuggestionID } ?? 0
        let delta = direction == .down ? 1 : -1
        selectedSuggestionID = suggestions[(current + delta + suggestions.count) % suggestions.count].id
    }

    private func add(_ location: WeatherLocation) {
        suggestions = []
        selectedSuggestionID = nil
        query = ""
        Task { await store.add(location) }
    }
}

private struct WeatherRowDropDelegate: DropDelegate {
    let targetID: Int
    @Binding var draggingID: Int?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        move(draggingID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct WeatherListRow: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.location.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.location.subtitle.isEmpty ? snapshot.location.timezone : snapshot.location.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: WeatherCondition.symbol(
                        for: snapshot.current.weatherCode,
                        isDay: snapshot.current.isDay
                    ))
                    .foregroundStyle(.blue)
                    Text(temperature(snapshot.current.temperature))
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                Text(WeatherCondition.title(for: snapshot.current.weatherCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func temperature(_ value: Double) -> String { String(format: "%.0f°", value) }
}

private struct WeatherDetailView: View {
    let snapshot: WeatherSnapshot
    let dataSource: WeatherDataSource
    let isLoading: Bool
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                currentHeader
                metricGrid
                hourlyForecast
                dailyForecast
                footer
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.location.name).font(.title2.bold())
                Text(snapshot.location.subtitle.isEmpty ? snapshot.location.timezone : snapshot.location.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(WeatherCondition.title(for: snapshot.current.weatherCode))
                    .font(.headline)
            }
            Spacer()
            Image(systemName: WeatherCondition.symbol(
                for: snapshot.current.weatherCode,
                isDay: snapshot.current.isDay
            ))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 42, weight: .medium))
            Text(String(format: "%.0f°", snapshot.current.temperature))
                .font(.system(size: 42, weight: .bold, design: .rounded))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.10), Color.cyan.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            WeatherMetric(title: "体感", value: String(format: "%.0f°", snapshot.current.apparentTemperature), symbol: "thermometer.medium")
            WeatherMetric(title: "湿度", value: "\(snapshot.current.humidity)%", symbol: "humidity.fill")
            WeatherMetric(title: "降水", value: String(format: "%.1f mm", snapshot.current.precipitation), symbol: "drop.fill")
            WeatherMetric(
                title: "风",
                value: "\(WeatherCondition.windDirection(snapshot.current.windDirection)) \(String(format: "%.0f", snapshot.current.windSpeed)) km/h",
                symbol: "wind"
            )
        }
    }

    private var hourlyForecast: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("未来 24 小时").font(.subheadline.weight(.semibold))
            if snapshot.hourly.isEmpty {
                Label("当前数据源暂无逐小时预报", systemImage: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.hourly) { hour in
                            VStack(spacing: 7) {
                                Text(hourLabel(hour.time))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Image(systemName: WeatherCondition.symbol(for: hour.weatherCode))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 18))
                                    .frame(height: 20)
                                Text(String(format: "%.0f°", hour.temperature))
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                Label(probabilityText(hour.precipitationProbability), systemImage: "drop.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                            }
                            .frame(width: 58)
                            .padding(.vertical, 9)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var dailyForecast: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("未来 7 天").font(.subheadline.weight(.semibold))
            ForEach(Array(snapshot.daily.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 10) {
                    Text(index == 0 ? "今天" : weekday(day.date))
                        .font(.caption.weight(.medium))
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: WeatherCondition.symbol(for: day.weatherCode))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 22)
                    Text(WeatherCondition.title(for: day.weatherCode))
                        .font(.caption)
                        .frame(width: 62, alignment: .leading)
                    Label(probabilityText(day.precipitationProbability), systemImage: "drop.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .frame(width: 52, alignment: .leading)
                    Spacer()
                    Text("\(String(format: "%.0f°", day.minimumTemperature))  /  \(String(format: "%.0f°", day.maximumTemperature))")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(index.isMultiple(of: 2) ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text("本地刷新 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Text(dataSource.title)
                Button(action: refresh) {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Label("刷新", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(LumaTextButtonStyle())
                .disabled(isLoading)
            }
            Text("天气数据仅在新增地点或手动刷新时请求。")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func hourLabel(_ value: String) -> String {
        guard let marker = value.lastIndex(of: "T") else { return value }
        return String(value[value.index(after: marker)...].prefix(5))
    }

    private func weekday(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return String(value.suffix(5)) }
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func probabilityText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "—"
    }
}

private struct WeatherMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

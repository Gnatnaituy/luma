import SwiftUI
import UniformTypeIdentifiers

struct StocksPluginView: View {
    @ObservedObject var store: StockStore
    @State private var query = ""
    @State private var suggestions: [StockSearchResult] = []
    @State private var selectedSuggestionID: String?
    @State private var draggingSymbol: String?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    TextField("代码或名称", text: $query)
                        .textFieldStyle(LumaTextFieldStyle())
                        .focused($isQueryFocused)
                        .onSubmit { performQuery() }
                        .onMoveCommand(perform: performSuggestionMove)
                    Button { performQuery() } label: {
                        if store.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .disabled(store.isBusy || query.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !store.records.isEmpty {
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            if store.isRefreshingAll {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(LumaIconButtonStyle())
                        .disabled(store.isBusy)
                        .help(store.isRefreshingAll ? "正在全部刷新" : "全部刷新")
                    }
                }
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if isQueryFocused, !suggestions.isEmpty {
                        stockSuggestionPanel
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
                    ContentUnavailableView("添加股票", systemImage: "plus.circle", description: Text("输入股票代码或名称搜索"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.records) { stock in
                                WindowDragExclusion {
                                    StockListRow(stock: stock, colorTheme: store.colorTheme)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                        .background(
                                            store.selectedSymbol == stock.symbol ? Color.accentColor.opacity(0.14) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .onTapGesture {
                                            store.select(stock)
                                        }
                                        .onDrag {
                                            draggingSymbol = stock.symbol
                                            return NSItemProvider(object: NSString(string: stock.symbol))
                                        }
                                        .onDrop(
                                            of: [UTType.text],
                                            delegate: StockRowDropDelegate(
                                                targetSymbol: stock.symbol,
                                                draggingSymbol: $draggingSymbol,
                                                move: { source, target in
                                                    store.move(source, before: target)
                                                }
                                            )
                                        )
                                        .contextMenu {
                                            Button("移除记录", role: .destructive) { store.remove(stock) }
                                        }
                                        .accessibilityAddTraits(.isButton)
                                }
                                .lumaContentTransition()
                            }
                        }
                        .padding(.horizontal, 6)
                        .animation(LumaMotion.standard, value: store.records.map(\.symbol))
                    }
                }
            }
            .frame(width: 218)
            .background(Color.primary.opacity(0.025))

            Divider()

            ZStack(alignment: .topLeading) {
                if let stock = store.selected {
                    StockDetailView(
                        stock: stock,
                        store: store,
                        colorTheme: store.colorTheme
                    ) {
                        Task {
                            await store.refreshSelected()
                            if let refreshed = store.selected {
                                await store.loadChart(for: refreshed, period: store.chartPeriod, force: true)
                            }
                        }
                    }
                    .id(stock.symbol)
                    .lumaContentTransition()
                } else {
                    ContentUnavailableView("还没有行情记录", systemImage: "chart.line.uptrend.xyaxis", description: Text("支持 A 股、港股和美股代码"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .lumaContentTransition()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(LumaMotion.quick, value: store.selectedSymbol)
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
            await store.query(value)
            if store.errorMessage.isEmpty { query = "" }
        }
    }

    private var stockSuggestionPanel: some View {
        VStack(spacing: 2) {
            ForEach(suggestions) { suggestion in
                Button { add(suggestion) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text("\(suggestion.symbol) · \(suggestion.market)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        selectedSuggestionID == suggestion.id ? Color.accentColor.opacity(0.12) : Color.clear,
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
        guard !value.isEmpty else {
            suggestions = []
            selectedSuggestionID = nil
            return
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        do {
            let results = try await EastMoneyStockSearchService().search(value)
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

    private func add(_ suggestion: StockSearchResult) {
        suggestions = []
        selectedSuggestionID = nil
        query = ""
        Task { await store.query(suggestion.symbol) }
    }
}

private struct StockRowDropDelegate: DropDelegate {
    let targetSymbol: String
    @Binding var draggingSymbol: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingSymbol, draggingSymbol != targetSymbol else { return }
        move(draggingSymbol, targetSymbol)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSymbol = nil
        return true
    }
}

private struct StockListRow: View {
    let stock: StockSnapshot
    let colorTheme: StockColorTheme

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stock.symbol).font(.system(.body, design: .rounded).weight(.semibold))
                Text(stock.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(stock.price.formatted(.number.precision(.fractionLength(2...3))))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text(String(format: "%+.2f%%", stock.changePercent))
                    .font(.caption2)
                    .foregroundStyle(colorTheme.color(isRising: stock.isRising))
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct StockDetailView: View {
    let stock: StockSnapshot
    @ObservedObject var store: StockStore
    let colorTheme: StockColorTheme
    let refresh: () -> Void
    @State private var selectedPeriod: StockChartPeriod = .defaultSelection

    private var points: [StockPoint] {
        if store.chartPeriod == selectedPeriod, !store.chartPoints.isEmpty { return store.chartPoints }
        return selectedPeriod == .daily ? stock.points : []
    }

    private var periodChangePercent: Double? {
        guard let first = points.first?.close, first != 0, let last = points.last?.close else { return nil }
        return (last - first) / first * 100
    }

    private var periodHigh: Double? {
        points.compactMap { $0.high ?? $0.close }.max()
    }

    private var periodLow: Double? {
        points.compactMap { $0.low ?? $0.close }.min()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(stock.name).font(.title2.bold())
                        HStack(spacing: 6) {
                            Text(stock.symbol)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            Text(stock.marketName)
                            Text(stock.currency)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(stock.price.formatted(.number.precision(.fractionLength(2...3))))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(String(format: "%+.2f  %+.2f%%", stock.change, stock.changePercent))
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(colorTheme.color(isRising: stock.isRising))
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("\(selectedPeriod.title)走势").font(.subheadline.weight(.semibold))
                        Text("\(points.count) 个数据点")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let change = periodChangePercent {
                            Text("区间 \(String(format: "%+.2f%%", change))")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(colorTheme.color(isRising: change >= 0))
                        }
                    }

                    StockPeriodSelector(selection: $selectedPeriod)

                    ZStack {
                        StockChart(
                            points: points,
                            period: selectedPeriod,
                            rising: (periodChangePercent ?? stock.changePercent) >= 0,
                            colorTheme: colorTheme
                        )
                        .frame(height: 165)
                        if store.isLoadingChart {
                            ProgressView()
                                .controlSize(.small)
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if !store.chartErrorMessage.isEmpty {
                        Text(store.chartErrorMessage)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if selectedPeriod == .intraday, !points.isEmpty {
                        HStack {
                            Text("09:15")
                            Spacer()
                            Text("11:30 / 13:00")
                            Spacer()
                            Text("15:30")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else if let first = points.first, let last = points.last {
                        HStack {
                            Text(chartDate(first.date))
                            Spacer()
                            if let low = periodLow, let high = periodHigh {
                                Text("低 \(formatPrice(low))  ·  高 \(formatPrice(high))")
                            }
                            Spacer()
                            Text(chartDate(last.date))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))

                StockDayRange(stock: stock, colorTheme: colorTheme)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    StockMetric(title: "今开", value: stock.open)
                    StockMetric(title: "最高", value: stock.high)
                    StockMetric(title: "最低", value: stock.low)
                    StockMetric(title: "昨收", value: stock.previousClose)
                    StockMetric(title: "成交量", text: stock.volume.formatted(.number.notation(.compactName)))
                    StockMetric(title: "振幅", text: String(format: "%.2f%%", stock.amplitudePercent))
                    StockMetric(title: "开盘涨跌", text: String(format: "%+.2f%%", stock.openChangePercent))
                    StockMetric(
                        title: "区间涨跌",
                        text: periodChangePercent.map { String(format: "%+.2f%%", $0) } ?? "—"
                    )
                    StockMetric(
                        title: "总值",
                        text: formatMarketValue(stock.totalMarketValue, currency: stock.currency)
                    )
                    StockMetric(
                        title: "流值",
                        text: formatMarketValue(stock.circulatingMarketValue, currency: stock.currency)
                    )
                    StockMetric(
                        title: "市盈",
                        text: stock.priceEarningsRatio.map { String(format: "%.2f", $0) } ?? "—"
                    )
                    StockMetric(title: "行业", text: stock.industry ?? "—")
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text(stock.quoteTime.isEmpty ? "行情时间 —" : "行情时间 \(stock.quoteTime)")
                    Text("·")
                    Text("本地刷新 \(stock.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    Spacer()
                    Text(store.dataSource.title)
                    Button(action: refresh) {
                        if store.isBusy || store.isLoadingChart {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(LumaTextButtonStyle())
                    .disabled(store.isBusy || store.isLoadingChart)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("行情数据仅在新增股票或手动刷新时请求。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(stock.symbol):\(selectedPeriod.rawValue):\(store.dataSource.rawValue)") {
            await store.loadChart(for: stock, period: selectedPeriod)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }

    private func chartDate(_ value: String) -> String {
        if selectedPeriod == .intraday { return String(value.suffix(4)) }
        if selectedPeriod == .fiveDay { return String(value.prefix(8)) }
        return String(value.prefix(10))
    }

    private func formatMarketValue(_ value: Double?, currency: String) -> String {
        guard let value else { return "—" }
        let prefix: String
        switch currency {
        case "CNY": prefix = "¥"
        case "HKD": prefix = "HK$"
        case "USD": prefix = "$"
        default: prefix = ""
        }
        if value >= 1_000_000_000_000 {
            return "\(prefix)\(String(format: "%.2f", value / 1_000_000_000_000))万亿"
        }
        if value >= 100_000_000 {
            return "\(prefix)\(String(format: "%.2f", value / 100_000_000))亿"
        }
        if value >= 10_000 {
            return "\(prefix)\(String(format: "%.2f", value / 10_000))万"
        }
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

private struct StockPeriodSelector: View {
    @Binding var selection: StockChartPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StockChartPeriod.allCases) { period in
                Button {
                    selection = period
                } label: {
                    Text(period.title)
                        .font(.caption.weight(selection == period ? .semibold : .regular))
                        .foregroundStyle(selection == period ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            selection == period ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct StockDayRange: View {
    let stock: StockSnapshot
    let colorTheme: StockColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日内位置").font(.subheadline.weight(.semibold))
                Spacer()
                Text(stock.dayPosition.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(colorTheme.color(isRising: stock.isRising))
            }
            GeometryReader { geometry in
                let position = stock.dayPosition ?? 0.5
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(colorTheme.color(isRising: stock.isRising).opacity(0.65))
                        .frame(width: max(8, width * position))
                    Circle()
                        .fill(colorTheme.color(isRising: stock.isRising))
                        .frame(width: 10, height: 10)
                        .offset(x: min(max(width * position - 5, 0), max(width - 10, 0)))
                }
            }
            .frame(height: 10)
            HStack {
                Text("最低 \(formatPrice(stock.low))")
                Spacer()
                Text("现价 \(formatPrice(stock.price))")
                Spacer()
                Text("最高 \(formatPrice(stock.high))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }
}

private struct StockMetric: View {
    let title: String
    let text: String

    init(title: String, value: Double) {
        self.title = title
        self.text = value.formatted(.number.precision(.fractionLength(2...3)))
    }

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.system(.caption, design: .monospaced).weight(.medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StockChart: View {
    let points: [StockPoint]
    let period: StockChartPeriod
    let rising: Bool
    let colorTheme: StockColorTheme

    var body: some View {
        GeometryReader { geometry in
            if points.count < 2 {
                ContentUnavailableView("暂无走势数据", systemImage: "chart.xyaxis.line")
            } else {
                let renderPoints = period.isCandlestick
                    ? points
                    : StockChartSampler.downsample(points, maximumCount: 360)
                let values = renderPoints.flatMap { point in
                    period.isCandlestick ? [point.high ?? point.close, point.low ?? point.close] : [point.close]
                }
                let minimum = values.min() ?? 0
                let maximum = values.max() ?? 1
                let spread = max(maximum - minimum, 0.0001)
                let leftInset: CGFloat = 10
                let rightInset: CGFloat = 54
                let topInset: CGFloat = 12
                let bottomInset: CGFloat = 12
                let plotWidth = max(1, geometry.size.width - leftInset - rightInset)
                let plotHeight = max(1, geometry.size.height - topInset - bottomInset)
                let xPosition: (Int, StockPoint) -> CGFloat = { index, point in
                    if period == .intraday, let ratio = StockTradingTimeline.ratio(for: point.date) {
                        return leftInset + plotWidth * CGFloat(ratio)
                    }
                    return plotWidth * CGFloat(index) / CGFloat(renderPoints.count - 1) + leftInset
                }
                let path = Path { path in
                    for (index, point) in renderPoints.enumerated() {
                        let x = xPosition(index, point)
                        let ratio = (point.close - minimum) / spread
                        let y = geometry.size.height - bottomInset - plotHeight * CGFloat(ratio)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                let areaPath = Path { path in
                    let firstX = renderPoints.first.map { xPosition(0, $0) } ?? leftInset
                    path.move(to: CGPoint(x: firstX, y: geometry.size.height - bottomInset))
                    for (index, point) in renderPoints.enumerated() {
                        let x = xPosition(index, point)
                        let ratio = (point.close - minimum) / spread
                        let y = geometry.size.height - bottomInset - plotHeight * CGFloat(ratio)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    let lastIndex = renderPoints.count - 1
                    let lastX = renderPoints.last.map { xPosition(lastIndex, $0) } ?? leftInset
                    path.addLine(to: CGPoint(x: lastX, y: geometry.size.height - bottomInset))
                    path.closeSubpath()
                }
                let lineColor = colorTheme.color(isRising: rising)
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        let ratio = Double(index) / 3
                        let y = topInset + plotHeight * CGFloat(index) / 3
                        Path { grid in
                            grid.move(to: CGPoint(x: leftInset, y: y))
                            grid.addLine(to: CGPoint(x: leftInset + plotWidth, y: y))
                        }
                        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        Text(formatPrice(maximum - spread * ratio))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .position(x: geometry.size.width - rightInset / 2, y: y)
                    }
                    if period == .intraday {
                        ForEach(Array(StockTradingTimeline.gridRatios.enumerated()), id: \.offset) { _, ratio in
                            let x = leftInset + plotWidth * CGFloat(ratio)
                            Path { grid in
                                grid.move(to: CGPoint(x: x, y: topInset))
                                grid.addLine(to: CGPoint(x: x, y: geometry.size.height - bottomInset))
                            }
                            .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }
                    }
                    if period.isCandlestick && renderPoints.allSatisfy(\.hasOHLC) {
                        ForEach(renderPoints.indices, id: \.self) { index in
                            let point = renderPoints[index]
                            let open = point.open ?? point.close
                            let high = point.high ?? point.close
                            let low = point.low ?? point.close
                            let x = xPosition(index, point)
                            let openY = geometry.size.height - bottomInset - plotHeight * CGFloat((open - minimum) / spread)
                            let closeY = geometry.size.height - bottomInset - plotHeight * CGFloat((point.close - minimum) / spread)
                            let highY = geometry.size.height - bottomInset - plotHeight * CGFloat((high - minimum) / spread)
                            let lowY = geometry.size.height - bottomInset - plotHeight * CGFloat((low - minimum) / spread)
                            let candleColor = colorTheme.color(isRising: point.close >= open)
                            let candleWidth = max(2, min(8, plotWidth / CGFloat(renderPoints.count) * 0.62))
                            Path { wick in
                                wick.move(to: CGPoint(x: x, y: highY))
                                wick.addLine(to: CGPoint(x: x, y: lowY))
                            }
                            .stroke(candleColor, lineWidth: 1)
                            Rectangle()
                                .fill(candleColor)
                                .frame(width: candleWidth, height: max(1.5, abs(closeY - openY)))
                                .position(x: x, y: (openY + closeY) / 2)
                        }
                    } else {
                        areaPath.fill(
                            LinearGradient(
                                colors: [lineColor.opacity(0.18), lineColor.opacity(0.015)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        path.stroke(
                            lineColor,
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                        )
                    }
                }
            }
        }
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }
}

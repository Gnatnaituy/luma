import AppKit
import SwiftUI

struct QuicklinksPluginView: View {
    @ObservedObject var store: QuicklinkStore
    @State private var name = ""
    @State private var keyword = ""
    @State private var template = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                TextField("名称", text: $name).textFieldStyle(LumaTextFieldStyle()).focused($focused)
                TextField("关键词", text: $keyword).textFieldStyle(LumaTextFieldStyle()).frame(width: 130)
                TextField("URL 或路径，可用 {query}", text: $template).textFieldStyle(LumaTextFieldStyle())
                Button("添加") {
                    store.add(name: name, template: template, keyword: keyword)
                    name = ""; keyword = ""; template = ""
                }
                .buttonStyle(LumaTextButtonStyle())
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        HStack {
                            Image(systemName: "link").foregroundStyle(.mint)
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text("\(item.keyword) · \(item.template)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) { store.remove(item) } label: { Image(systemName: "trash") }
                                .buttonStyle(LumaIconButtonStyle())
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            }
            if store.items.isEmpty {
                ContentUnavailableView("还没有 Quicklink", systemImage: "link.badge.plus", description: Text("支持 {query}、{clipboard}、{selectedText} 和 {date}"))
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }
}

struct SnippetsPluginView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var name = ""
    @State private var keyword = ""
    @State private var content = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                TextField("名称", text: $name).textFieldStyle(LumaTextFieldStyle()).focused($focused)
                TextField("关键词", text: $keyword).textFieldStyle(LumaTextFieldStyle()).frame(width: 130)
                TextField("片段内容", text: $content).textFieldStyle(LumaTextFieldStyle())
                Button("添加") {
                    store.add(name: name, content: content, keyword: keyword)
                    name = ""; keyword = ""; content = ""
                }
                .buttonStyle(LumaTextButtonStyle())
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button { clipboard.copy(item.content) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(LumaIconButtonStyle()).help("复制")
                            Button(role: .destructive) { store.remove(item) } label: { Image(systemName: "trash") }
                                .buttonStyle(LumaIconButtonStyle())
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            }
            if store.items.isEmpty {
                ContentUnavailableView("还没有片段", systemImage: "text.quote", description: Text("保存常用文本后可从主搜索直接查找并复制"))
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }
}

struct CalendarPluginView: View {
    @ObservedObject var store: CalendarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("未来 14 天").font(.headline)
                Spacer()
                Button { Task { await store.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .buttonStyle(LumaTextButtonStyle())
            }
            if store.authorizationDenied {
                ContentUnavailableView("需要日历权限", systemImage: "calendar.badge.exclamationmark", description: Text("请在系统设置中允许 Luma 访问日历"))
            } else if store.events.isEmpty {
                ContentUnavailableView("近期没有日程", systemImage: "calendar", description: Text("Luma 会读取系统日历，不会上传日程"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.events, id: \.eventIdentifier) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.headline)
                                    Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("加入会议") { store.join(event) }
                                    .buttonStyle(LumaTextButtonStyle())
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(24)
        .task { await store.refresh() }
    }
}

struct WindowManagementPluginView: View {
    let arrange: (WindowLayout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("排列唤起 Luma 前聚焦的窗口").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(WindowLayout.allCases) { layout in
                    Button { arrange(layout) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: layout.symbol).font(.system(size: 30))
                            Text(layout.title).font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                    }
                    .buttonStyle(LumaTextButtonStyle())
                }
            }
            Label("需要“辅助功能”权限；布局应用在当前聚焦屏幕。", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}

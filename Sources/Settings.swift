import Cocoa
import SwiftUI

struct ThemeRegistry: Decodable {
    let themes: [Theme]
}

struct Theme: Decodable, Identifiable {
    let id: String
    let name: String
    let desc: String
    let page: String
    let groups: [ParameterGroup]

    var defaults: [String: Double] {
        Dictionary(uniqueKeysWithValues: groups.flatMap(\.params).map { ($0.key, $0.defaultValue) })
    }
}

struct ParameterGroup: Decodable, Identifiable {
    let name: String
    let params: [ThemeParameter]
    var id: String { name }
}

struct ThemeParameter: Decodable, Identifiable {
    let key: String
    let label: String
    let hint: String?
    let min: Double?
    let max: Double?
    let step: Double?
    let defaultValue: Double
    let unit: String?
    let format: String?
    let options: [String]?
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, hint, min, max, step, unit, format, options
        case defaultValue = "default"
    }

    func sanitize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        let lower = min ?? 0
        let upper = max ?? Double((options?.count ?? 2) - 1)
        let increment = step ?? 1
        let rounded = lower + ((value - lower) / increment).rounded() * increment
        return Swift.min(upper, Swift.max(lower, rounded))
    }

    func display(_ value: Double) -> String {
        if format == "percent" { return String(format: "%.0f%%", value * 100) }
        if format == "times" { return String(format: "%.2f×", value) }
        return value.formatted(.number.precision(.fractionLength(0...2))) + (unit.map { " " + $0 } ?? "")
    }
}

final class AppSettings: ObservableObject {
    enum Change { case theme, parameters, playback }
    let themes: [Theme]
    private let defaults: UserDefaults
    var onChange: ((Change) -> Void)?

    @Published var themeID: String {
        didSet {
            guard themeID != oldValue else { return }
            defaults.set(themeID, forKey: "theme")
            onChange?(.theme)
        }
    }
    @Published var parameters: [String: [String: Double]] {
        didSet { defaults.set(parameters, forKey: "parameters"); onChange?(.parameters) }
    }
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused"); onChange?(.playback) } }
    @Published var autoPause: Bool { didSet { defaults.set(autoPause, forKey: "autoPause"); onChange?(.playback) } }
    @Published var iconStatus = "正在检查桌面图标…"
    @Published var needsPermission = false
    @Published var renderError: String?
    @Published var screenCount = 0

    var theme: Theme { themes.first { $0.id == themeID } ?? themes[0] }
    var currentParameters: [String: Double] { parameters[themeID] ?? theme.defaults }

    init(resourceURL: URL, defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        themes = try JSONDecoder().decode(ThemeRegistry.self, from: Data(contentsOf: resourceURL.appendingPathComponent("themes.json"))).themes
        guard !themes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let savedTheme = defaults.string(forKey: "theme") ?? "beach"
        themeID = themes.contains { $0.id == savedTheme } ? savedTheme : themes[0].id
        let saved = defaults.dictionary(forKey: "parameters") as? [String: [String: Double]] ?? [:]
        parameters = Dictionary(uniqueKeysWithValues: themes.map { theme in
            let values = Dictionary(uniqueKeysWithValues: theme.groups.flatMap(\.params).map { parameter in
                (parameter.key, parameter.sanitize(saved[theme.id]?[parameter.key] ?? parameter.defaultValue))
            })
            return (theme.id, values.merging(["seed": saved[theme.id]?["seed"] ?? 421337]) { old, _ in old })
        })
        paused = defaults.bool(forKey: "paused")
        autoPause = defaults.object(forKey: "autoPause") as? Bool ?? true
    }

    func setParameter(_ parameter: ThemeParameter, value: Double) {
        parameters[themeID, default: theme.defaults][parameter.key] = parameter.sanitize(value)
    }

    func shuffle() { parameters[themeID, default: theme.defaults]["seed"] = Double.random(in: 1...999999).rounded() }
    func reset() { parameters[themeID] = theme.defaults.merging(["seed": 421337]) { old, _ in old } }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let resourceURL: URL
    let requestPermission: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "water.waves").font(.system(size: 30)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("岸屿 Shoreline").font(.title2.bold())
                    Text("让桌面图标成为风景的一部分").foregroundStyle(.secondary)
                }
                Spacer()
                Button(settings.paused ? "继续动画" : "暂停动画") { settings.paused.toggle() }
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    permissionPanel
                    if let error = settings.renderError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack(spacing: 14) {
                        ForEach(settings.themes) { theme in
                            Button { settings.themeID = theme.id } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let image = NSImage(contentsOf: resourceURL.appendingPathComponent("thumbs/\(theme.id).webp")) {
                                        Image(nsImage: image).resizable().scaledToFill().frame(height: 116).clipped()
                                    }
                                    HStack {
                                        Text(theme.name).font(.headline)
                                        Spacer()
                                        Image(systemName: settings.themeID == theme.id ? "checkmark.circle.fill" : "circle")
                                    }.padding(.horizontal, 12)
                                    Text(theme.desc).font(.caption).foregroundStyle(.secondary)
                                        .frame(height: 34, alignment: .topLeading).padding(.horizontal, 12).padding(.bottom, 10)
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color.primary.opacity(0.035))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(settings.themeID == theme.id ? Color.teal : Color.clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityIdentifier("theme-\(theme.id)")
                        }
                    }
                    HStack {
                        Text("\(settings.theme.name)设置").font(.headline)
                        Spacer()
                        Button("换一张", action: settings.shuffle)
                        Button("恢复默认", action: settings.reset)
                    }
                    ForEach(settings.theme.groups) { group in
                        GroupBox {
                            VStack(spacing: 14) {
                                ForEach(group.params) { parameter in parameterView(parameter) }
                            }.padding(10)
                        } label: { Text(group.name) }
                    }
                    Toggle("可见窗口铺满屏幕时自动暂停该屏动画", isOn: $settings.autoPause)
                    Text("\(settings.screenCount) 块显示器 · 最高 30 fps · 退出后显示系统原壁纸")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("基于 Deskland Preview 的沙滩与草地主题，GPL-3.0。独立 macOS 移植。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }
        }.frame(minWidth: 620, minHeight: 680)
    }

    private var permissionPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: settings.needsPermission ? "hand.raised" : "desktopcomputer")
                .foregroundStyle(settings.needsPermission ? .orange : .teal).font(.title2)
            VStack(alignment: .leading, spacing: 5) {
                Text(settings.iconStatus).font(.headline).accessibilityIdentifier("icon-status")
                Text(settings.needsPermission
                     ? "在系统设置 → 隐私与安全性 → 辅助功能中开启 Shoreline，授权后会自动读取图标位置。"
                     : "读取 Finder 桌面图标边界，移动图标后风景会平滑调整。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if settings.needsPermission { Button("打开授权设置", action: requestPermission) }
        }.padding(14).background(Color.teal.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func parameterView(_ parameter: ThemeParameter) -> some View {
        let binding = Binding<Double>(
            get: { settings.currentParameters[parameter.key] ?? parameter.defaultValue },
            set: { settings.setParameter(parameter, value: $0) }
        )
        VStack(alignment: .leading, spacing: 4) {
            if let options = parameter.options {
                Picker(parameter.label, selection: binding) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, label in Text(label).tag(Double(index)) }
                }.pickerStyle(.segmented)
            } else {
                HStack {
                    Text(parameter.label)
                    Spacer()
                    Text(parameter.display(binding.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: binding, in: (parameter.min ?? 0)...(parameter.max ?? 1), step: parameter.step ?? 1)
            }
            if let hint = parameter.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

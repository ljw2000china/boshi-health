import SwiftUI

/// TabView 骨架：训练 / 今日 / 趋势 / 设置
struct ContentView: View {

    @EnvironmentObject private var hk: HKService
    @AppStorage(SleepWriteback.enabledKey) private var sleepWritebackEnabled = true

    var body: some View {
        TabView {
            trainingTab
                .tabItem { Label("训练", systemImage: "figure.strengthtraining.traditional") }
            todayTab
                .tabItem { Label("今日", systemImage: "sun.max") }
            NavigationStack { TrendsView() }
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
            settingsTab
                .tabItem { Label("设置", systemImage: "gear") }
        }
    }

    // MARK: - 训练（第一页）

    private var trainingTab: some View {
        NavigationStack {
            TrainingHomeView()
        }
    }

    // MARK: - 今日

    private var todayTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    OverviewView()

                    NavigationLink {
                        CheckinView()
                    } label: {
                        Label("今日打卡", systemImage: "hand.thumbsup")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink {
                        DebugDataView()
                    } label: {
                        Label("调试数据", systemImage: "wrench.and.screwdriver")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    authStateCard
                }
                .padding(.horizontal)
            }
            .navigationTitle("薄士")
        }
    }

    // MARK: - 设置

    private var settingsTab: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("睡眠同步到健康", isOn: $sleepWritebackEnabled)
                    Text("将手表推测的睡眠时段写入健康 App（仅在健康中没有原生睡眠数据时；开启后重算最近 7 天）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("健康")
                }
                Section {
                    NavigationLink("调试数据") {
                        DebugDataView()
                    }
                } header: {
                    Text("开发者")
                }
                Section {
                    Text("薄士 · 个人健康监控")
                        .foregroundStyle(.secondary)
                    Text("数据全部本地存储，不上传服务器")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .onChange(of: sleepWritebackEnabled) { _, newValue in
                SleepWriteback.isEnabled = newValue
                if newValue {
                    Task { await DataPipeline.shared.rebuildRecent(days: 7) }
                }
            }
        }
    }

    // MARK: - 通用占位

    private func placeholderTab(title: String, message: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 授权状态卡

    @ViewBuilder
    private var authStateCard: some View {
        switch hk.authState {
        case .unavailable:
            Label("此设备不支持健康数据", systemImage: "exclamationmark.triangle")
                .font(.footnote)
        case .notRequested, .failed:
            VStack(spacing: 6) {
                Label("等待健康数据授权", systemImage: "heart.text.square")
                    .font(.footnote)
                Button("重新请求授权") {
                    Task { await hk.requestAuthorizationIfNeeded() }
                }
                .font(.footnote)
            }
        case .requested:
            Label("已请求健康数据授权", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }
}
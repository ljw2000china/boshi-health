import SwiftUI

/// 手机调试页：类型汇总列表（最新值/更新时间/24h 计数），点入看样本明细。
struct DebugDataView: View {

    @EnvironmentObject private var hk: HKService
    @State private var summaries: [DebugTypeSummary] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var showDeniedHint = false

    var body: some View {
        Group {
            switch hk.authState {
            case .unavailable:
                ContentUnavailableView("此设备不支持健康数据", systemImage: "exclamationmark.triangle")
            case .notRequested, .failed:
                waitingView
            case .requested:
                listContent
            }
        }
        .scrollContentBackground(.hidden)
        .themedSurface()
        .navigationTitle("调试数据")
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await reload() }
            }
        }
        .onChange(of: hk.authState) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - 等待授权

    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(PulseDesign.labelSecondary)
            Text("等待健康数据授权")
                .font(.headline)
            Text("请在「健康」App → 头像 → App 与服务 中允许 Pulse 读取数据；也可直接在下方重新发起请求。")
                .font(.footnote)
                .foregroundStyle(PulseDesign.labelSecondary)
                .multilineTextAlignment(.center)
            Button("请求授权") {
                Task {
                    let before = hk.authState
                    await hk.requestAuthorizationIfNeeded()
                    // 状态未变说明系统不再弹授权框（已拒/已请求过），就地提示
                    if hk.authState == before { showDeniedHint = true }
                }
            }
            if showDeniedHint {
                Label("系统不再弹出授权框，请按上方指引在健康 App 中开启",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(PulseDesign.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
        }
        .padding()
    }

    // MARK: - 汇总列表

    private var listContent: some View {
        Group {
            if loading && summaries.isEmpty {
                ProgressView("读取中…")
            } else if summaries.isEmpty {
                ContentUnavailableView("暂无数据", systemImage: "tray")
            } else {
                List(summaries) { row in
                    if row.id == summaries.first?.id {
                        Section("睡眠") {
                            SleepDebugSection()
                        }
                    }
                    NavigationLink {
                        DebugSampleListView(typeIdentifier: row.typeIdentifier, title: row.displayName)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(row.latestValueText.isEmpty ? "暂无数据" : row.latestValueText)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(row.latestValueText.isEmpty ? .secondary : .primary)
                            }
                            HStack {
                                Text(row.latestDate.map { "更新于 \($0.formatted(date: .numeric, time: .shortened))" } ?? "—")
                                Spacer()
                                Text(row.last24hTruncated ? "24h 样本 ≥\(row.last24hCount) 条" : "24h 样本 \(row.last24hCount) 条")
                            }
                            .font(.footnote)
                            .foregroundStyle(PulseDesign.labelSecondary)
                        }
                    }
                }
                .refreshable {
                    await reload()
                }
            }
        }
    }

    // MARK: - 数据加载

    private func reload() async {
        guard hk.authState == .requested else { return }
        loading = true
        summaries = await hk.debugSummaries()
        loading = false
    }
}

/// 某类型的样本明细列表：值 / 起止时间 / 来源。
struct DebugSampleListView: View {

    let typeIdentifier: String
    let title: String

    @EnvironmentObject private var hk: HKService
    @State private var samples: [DebugSample] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("读取中…")
            } else if samples.isEmpty {
                ContentUnavailableView("暂无数据", systemImage: "tray")
            } else {
                List(samples) { sample in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample.valueText)
                            .font(.headline)
                            .fontDesign(.rounded)
                        Text("\(sample.startDate.formatted(date: .numeric, time: .shortened)) — \(sample.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                        Text("来源：\(sample.sourceName)")
                            .font(.footnote)
                            .foregroundStyle(PulseDesign.labelSecondary)
                    }
                }
            }
        }
        .navigationTitle(title)
        .task {
            samples = await hk.debugSamples(typeIdentifier: typeIdentifier)
            loading = false
        }
    }
}

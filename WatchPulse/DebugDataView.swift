import SwiftUI

/// 手表调试页：每类一行「类型 · 最新值 · 更新时间 · 24h 计数」，下拉刷新。
struct DebugDataView: View {

    @EnvironmentObject private var hk: HKService
    @State private var summaries: [DebugTypeSummary] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var showDeniedHint = false

    /// 次要文字统一 14pt（手表可读性下限）
    private let secondaryFont = Font.system(size: 14)

    var body: some View {
        Group {
            switch hk.authState {
            case .unavailable:
                bigStateMessage(icon: "exclamationmark.triangle", text: "此设备不支持健康数据")
            case .notRequested, .failed:
                waitingView
            case .requested:
                listContent
            }
        }
        .navigationTitle("调试数据")
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await reload() }
            }
        }
        .onChange(of: hk.authState) { _, _ in
            // 授权完成后自动刷新
            Task { await reload() }
        }
    }

    // MARK: - 等待授权

    private var waitingView: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("等待健康数据授权")
                .font(.headline)
            Text("请在 iPhone 的「健康」App → 头像 → App 与服务 中允许 Pulse 读取数据")
                .font(secondaryFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新请求授权") {
                Task {
                    let before = hk.authState
                    await hk.requestAuthorizationIfNeeded()
                    // 状态未变说明系统不再弹授权框（已拒/已请求过），就地提示
                    if hk.authState == before { showDeniedHint = true }
                }
            }
            .font(secondaryFont)
            if showDeniedHint {
                stateMessage(icon: "info.circle", text: "系统不再弹出授权框，请按上方指引在健康 App 中开启")
            }
        }
        .padding()
    }

    // MARK: - 数据列表

    private var listContent: some View {
        Group {
            if loading && summaries.isEmpty {
                ProgressView("读取中…")
            } else if summaries.isEmpty {
                bigStateMessage(icon: "tray", text: "暂无数据")
            } else {
                List(summaries) { row in
                    if row.id == summaries.first?.id {
                        Section("睡眠") {
                            SleepDebugSection()
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.displayName)
                            .font(.subheadline)
                        HStack {
                            Text(row.latestValueText.isEmpty ? "暂无数据" : row.latestValueText)
                                .font(.headline)
                                .fontDesign(.rounded)
                            Spacer()
                            Text(row.last24hTruncated ? "24h ≥\(row.last24hCount)" : "24h ×\(row.last24hCount)")
                                .font(secondaryFont)
                                .foregroundStyle(.secondary)
                        }
                        Text(row.latestDate.map(timeText) ?? "—")
                            .font(secondaryFont)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .refreshable { await reload() }
                .listStyle(.plain)
            }
        }
    }

    private func stateMessage(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(secondaryFont)
                .multilineTextAlignment(.center)
        }
    }

    private func bigStateMessage(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.headline)
        }
    }

    // MARK: - 数据加载

    private func reload() async {
        guard hk.authState == .requested else { return }
        loading = true
        summaries = await hk.debugSummaries()
        loading = false
    }

    /// 时间展示：今天只显示时分，否则带日期
    private func timeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "更新于 " + date.formatted(date: .omitted, time: .shortened)
        }
        return "更新于 " + date.formatted(date: .numeric, time: .shortened)
    }
}

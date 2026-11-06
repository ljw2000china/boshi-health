import SwiftUI

/// 手机端：睡眠 / 健身 双 Tab 首页
struct ContentView: View {

    @EnvironmentObject private var hk: HKService
    @EnvironmentObject private var theme: ThemeStore

    @State private var tab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // 全局背景唯一真源（渐变 / 照片壁纸）
            ThemeBackgroundView(theme: theme)
                .ignoresSafeArea()

            // 三页并存，按选中显隐（保留各自导航栈状态）
            SleepHomeView()
                .environmentObject(hk)
                .opacity(tab == 0 ? 1 : 0)
                .disabled(tab != 0)
                .allowsHitTesting(tab == 0)
            FitnessHomeView()
                .opacity(tab == 1 ? 1 : 0)
                .disabled(tab != 1)
                .allowsHitTesting(tab == 1)
            SettingsView()
                .environmentObject(hk)
                .opacity(tab == 2 ? 1 : 0)
                .disabled(tab != 2)
                .allowsHitTesting(tab == 2)

            bottomBar
        }
        .environment(\.pulseCardOpacity, theme.cardOpacity)
        .environmentObject(theme)
    }

    // MARK: - 自定义底部导航（毛玻璃胶囊；不用 TabView，避开 UIKit 不透明底层）

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barItem(0, icon: "moon.zzz.fill", label: "睡眠")
            barItem(1, icon: "dumbbell.fill", label: "健身")
            barItem(2, icon: "gearshape.fill", label: "设置")
        }
        .frame(height: 56)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    private func barItem(_ index: Int, icon: String, label: String) -> some View {
        let selected = tab == index
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { tab = index }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? PulseDesign.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .scaleEffect(selected ? 1.05 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulseBouncyStyle())
    }
}

// MARK: - 睡眠页

struct SleepHomeView: View {

    @EnvironmentObject private var hk: HKService
    @EnvironmentObject private var theme: ThemeStore
    @State private var hasSleep = true
    @State private var report: [SleepDiagnostics.TypeReport] = []
    @State private var rebuilding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    OverviewView()

                    if !hasSleep {
                        sleepRepairCard
                    }

                    metricGuideCard

                    VStack(spacing: 10) {
                        PulseLinkCard(icon: "chart.bar.xaxis", iconColor: .purple,
                                      title: "趋势分析",
                                      subtitle: "睡眠 / 恢复 / 负荷长期走势") {
                            TrendsView()
                        }
                        PulseLinkCard(icon: "hand.thumbsup", iconColor: .green,
                                      title: "今日打卡",
                                      subtitle: "主观感受，帮助校准恢复分") {
                            CheckinView()
                        }
                    }

                    authStateCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .themedSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PageTitleBar(text: "薄士", theme: theme)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DebugDataView()
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(PulseDesign.accent)
                    }
                }
            }
            .task {
                await loadDiagnostics()
            }
        }
        .themeBackground()
    }

    // MARK: - 睡眠修复卡（空态时显示）

    private var sleepRepairCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.indigo)
                Text("还没有睡眠数据")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            Text("薄士需要「健康 App」里的睡眠记录（戴 Apple Watch 睡觉会自动记录）。\n检查下面各项 → 缺哪个补哪个：")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
                .lineSpacing(3)

            ForEach(report, id: \.identifier) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.count7d > 0 ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(r.count7d > 0 ? .green : .red)
                    Text(r.nameZh)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer()
                    if let d = r.lastSample {
                        Text(shortDate(d))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PulseDesign.labelSecondary)
                    } else {
                        Text("7 天内无样本")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
                .frame(minHeight: 28)
            }

            VStack(spacing: 10) {
                PulseProminentButton(rebuilding ? "正在重拉 60 天数据…" : "修复：重新授权并重拉数据",
                                     systemImage: "arrow.clockwise") {
                    Task { await repair() }
                }
                .disabled(rebuilding)

                Button("打开 健康 App 查看睡眠记录") {
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.indigo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard(padding: 16)
    }

    private func repair() async {
        rebuilding = true
        await hk.requestAuthorizationIfNeeded()
        await DataPipeline.shared.forceRebuild(days: 60)
        await loadDiagnostics()
        rebuilding = false
    }

    private func loadDiagnostics() async {
        let has = await DataPipeline.shared.hasAnySleepWindow()
        hasSleep = has
        if !has {
            report = await SleepDiagnostics.report()
        }
    }

    // MARK: - 指标说明

    private var metricGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(PulseDesign.accent)
                Text("指标说明")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            guideRow("恢复", "0–100", "身体恢复程度：心率变异性↑、静息心率↓、呼吸/腕温稳定、睡眠效率高 → 越高越满血。≥70 满状态；<45 建议降强度。")
            guideRow("睡眠分", "0–100", "综合睡眠时长、效率、规律性与深睡占比。")
            guideRow("Strain", "0–21", "全天运动负荷（心率区间分钟 + 日常活动量），越高越累，训练日越高越有效。")
            guideRow("压力", "0–100", "日间压力水平：白天心率变异性越低 → 压力越高。持续偏高注意放松。")
            guideRow("睡眠债", "小时", "近 14 天「该睡没睡够」的累计欠账，靠多睡偿还。")
            guideRow("准备度", "0–10", "今天适不适合上强度：恢复、睡眠债、训练负荷比（ACWR）三者综合。8+ 冲；4–8 正常练；<4 轻松动。")
            guideRow("ACWR", "甜区 0.8–1.3", "急性 ÷ 慢性训练负荷比，骤升超过 1.5 受伤风险高。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard(padding: 16)
    }

    private func guideRow(_ name: String, _ range: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                Text(range)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.accent)
            }
            Text(desc)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }

    // MARK: - 授权状态卡

    @ViewBuilder
    private var authStateCard: some View {
        switch hk.authState {
        case .unavailable:
            Label {
                Text("此设备不支持健康数据")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            .font(.footnote)
        case .notRequested, .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label("尚未获得健康数据授权", systemImage: "heart.text.square")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                PulseSecondaryButton("请求授权") {
                    Task { await hk.requestAuthorizationIfNeeded() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulseCard(padding: 14)
        case .requested:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("健康数据已授权")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulseCard(padding: 14)
        }
    }
}

// MARK: - 健身页

struct FitnessHomeView: View {

    @EnvironmentObject private var theme: ThemeStore

    @State private var active: Workout?
    @State private var summary: TrainingSummary.DaySummary = .empty(dayKey: "")
    @State private var showSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 今日练X日
                    focusBanner

                    // 大圆按钮（居中，整个圆可点）
                    bigStartButton
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                    // 健身相关入口
                    VStack(spacing: 10) {
                        PulseLinkCard(icon: "calendar", iconColor: PulseDesign.accent,
                                      title: "本周总结",
                                      subtitle: "肌群分布图 · 与上周对比") {
                            WeeklySummaryView()
                        }
                        PulseLinkCard(icon: "chart.line.uptrend.xyaxis", iconColor: PulseDesign.mint,
                                      title: "进步曲线",
                                      subtitle: "重量突破时间线 · 维持天数") {
                            ExerciseProgressView()
                        }
                        PulseLinkCard(icon: "clock.arrow.circlepath", iconColor: .blue,
                                      title: "训练历史",
                                      subtitle: "查看、修改、补记任何一天") {
                            WorkoutHistoryView()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .themedSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PageTitleBar(text: "健身", theme: theme)
                }
            }
            .task { await refresh() }
            .onChange(of: showSession) { _, showing in
                if !showing { Task { await refresh() } }
            }
            .fullScreenCover(isPresented: $showSession) {
                if let active {
                    TrainingSessionView(workoutID: active.id)
                }
            }
        }
        .themeBackground()
    }

    // MARK: - 区块

    private var focusBanner: some View {
        let snap = TrainingDaySnapshot.make(muscleGroups: summary.focus.muscles)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(summary.isEmpty ? snap.subtitle
                        : "今天 \(summary.totalSets) 组 · \(volumeText(summary.volumeKg))")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(snap.emoji)
                .font(.system(size: 32))
                .frame(width: 60, height: 60)
                .background(PulseDesign.accent.opacity(0.16), in: Circle())
        }
        .pulseCard(padding: 16)
    }

    private var bigStartButton: some View {
        let isActive = active != nil
        let diameter: CGFloat = 188
        return Button {
            Task {
                let session = await TrainingService.shared.startSession()
                active = session
                showSession = true
            }
        } label: {
            ZStack {
                // 呼吸光环
                Circle()
                    .fill(PulseDesign.accent.opacity(0.15))
                    .frame(width: diameter + 28, height: diameter + 28)
                    .scaleEffect(isActive ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                               value: isActive)
                Circle()
                    .fill(PulseDesign.mainGradient)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: PulseDesign.accent.opacity(0.45), radius: 16, y: 8)
                VStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 44, weight: .semibold))
                    Text(isActive ? "继续训练" : "开始健身")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    if !summary.isEmpty {
                        Text("已完成 \(summary.totalSets) 组")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(height: diameter + 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "继续训练" : "开始健身")
    }

    private func refresh() async {
        active = await TrainingService.shared.activeSession()
        summary = await TrainingService.shared.daySummary()
    }

    private func volumeText(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1ft", v / 1000) : String(format: "%.0fkg", v)
    }
}

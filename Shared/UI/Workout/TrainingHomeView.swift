import SwiftUI

/// 训练主页：开始/继续训练、今日练什么（自动识别「练X日」）、往下滑看今日总结。
public struct TrainingHomeView: View {

    @State private var active: Workout?
    @State private var summary: TrainingSummary.DaySummary = .empty(dayKey: "")
    @State private var showSession = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                focusBanner

                PulseProminentButton(active != nil ? "继续训练" : "开始训练",
                                     systemImage: active != nil ? "play.fill" : "figure.strengthtraining.traditional") {
                    Task {
                        let session = await TrainingService.shared.startSession()
                        active = session
                        showSession = true
                    }
                }

                if active != nil {
                    PulseSecondaryButton("结束锻炼", tint: .red) {
                        Task {
                            await TrainingService.shared.endSession(active?.id ?? "")
                            active = nil
                            await refresh()
                        }
                    }
                }

                if !summary.isEmpty {
                    todaySummary
                } else if active == nil {
                    Text("去健身房前点「开始训练」，选动作、记组，组间自动计时休息。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .themedSurface()
        .navigationTitle("训练")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - 区块

    private var focusBanner: some View {
        // 休息日与训练日都统一用可点按的跑马灯横幅（点按换文案 + 表情滚出/旋转）
        let rest = summary.isEmpty || summary.focus.muscles.isEmpty
        let snapshot = TrainingDaySnapshot.make(muscleGroups: summary.focus.muscles)
        return AnyView(
            RestDayBannerView(
                title: snapshot.title,
                emoji: rest ? TrainingDaySnapshot.restDayEmoji : snapshot.emoji,
                subtitle: snapshot.subtitle,
                onNewSubtitle: { seed in
                    rest ? TrainingDaySnapshot.restLine(for: seed)
                         : TrainingDaySnapshot.trainingLine(for: summary.focus.muscles.first ?? "力量")
                }
            )
        )
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日总结")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(summary.totalSets) 组 · \(volumeText(summary.volumeKg))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }

            ForEach(summary.exerciseOrder, id: \.self) { exID in
                let sets = summary.sets(for: exID)
                HStack(spacing: 10) {
                    Text(summary.exerciseName(exID))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(sets.count) 组")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                    Text(bestText(sets))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PulseDesign.accent)
                        .lineLimit(1)
                }
                .frame(minHeight: 26)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard(padding: 16)
    }

    // MARK: - 工具

    private func refresh() async {
        active = await TrainingService.shared.activeSession()
        summary = await TrainingService.shared.daySummary()
    }

    private func bestText(_ sets: [TrainingSummary.TrainingSet]) -> String {
        guard let best = sets.max(by: { $0.weightKg < $1.weightKg }) else { return "" }
        let w = best.weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", best.weightKg)
            : String(format: "%.1f", best.weightKg)
        return "\(w)kg×\(best.reps)"
    }

    private func volumeText(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1ft", v / 1000) : String(format: "%.0fkg", v)
    }

    private var titleSize: CGFloat {
        #if os(watchOS)
        22
        #else
        28
        #endif
    }
}

import SwiftUI

/// 训练会话主流程：
/// 选动作 → 记组（重量/次数 → 完成一组）→ 全屏休息倒计时 → 回来继续；
/// 左上角圆形箭头 = 换动作；底部 = 结束锻炼。
public struct TrainingSessionView: View {

    struct RestConfig: Identifiable {
        let id = UUID()
        var exerciseName: String
        var sec: Int
        var nextSetText: String
    }

    let workoutID: String

    @Environment(\.dismiss) private var dismiss
    @State private var selected: ExercisePickerView.Pick?
    @State private var weight: Double = 20
    @State private var reps: Double = 10
    @State private var lastText = ""
    @State private var suggestion: Double?
    @State private var mySets: [TrainingSummary.TrainingSet] = []
    @State private var sessionTotalSets = 0
    @State private var rest: RestConfig?
    @State private var confirmEnd = false
    @State private var busy = false

    public init(workoutID: String) {
        self.workoutID = workoutID
    }

    public var body: some View {
        ZStack {
            if let selected {
                loggingView(selected)
            } else {
                pickingView
            }
        }
        .fullScreenCover(item: $rest) { cfg in
            NavigationStack {
                RestTimerView(exerciseName: cfg.exerciseName, totalSec: cfg.sec,
                              nextSetText: cfg.nextSetText) {
                    Task { await refresh() }
                }
            }
        }
        .themedSurface()
        .task { await refresh() }
        .confirmationDialog("结束本次训练？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("结束锻炼", role: .destructive) {
                Task {
                    await TrainingService.shared.endSession(workoutID)
                    dismiss()
                }
            }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("共完成 \(sessionTotalSets) 组")
        }
    }

    // MARK: - 选动作

    private var pickingView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ExercisePickerView { pick in
                    selected = pick
                    Task { await loadExerciseDefaults(pick) }
                }
                if sessionTotalSets > 0 {
                    Button {
                        confirmEnd = true
                    } label: {
                        Text("结束锻炼（\(sessionTotalSets) 组）")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CircularBackButton { dismiss() }
                }
            }
        }
    }

    // MARK: - 记组

    @State private var editingWeight = false
    @State private var editingReps = false

    @ViewBuilder
    private func loggingView(_ ex: ExercisePickerView.Pick) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                // 顶部：换动作 + 动作名
                HStack(spacing: 10) {
                    CircularBackButton { selected = nil }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(ex.muscle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PulseDesign.labelSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)

                // 动作示意图
                ExerciseIllustrationView(muscleGroup: ex.muscle)
                    .frame(height: 128)

                // 重量 / 次数（上下排列，宽敞）
                VStack(spacing: 16) {
                    QuantityControl(title: "重量 kg（点数字直接输入）", value: $weight,
                                    step: 5, range: 0...999) { editingWeight = true }
                        .pulseCard(padding: 12)
                    QuantityControl(title: "次数（点数字直接输入）", value: $reps,
                                    step: 1, range: 0...999, isCount: true) { editingReps = true }
                        .pulseCard(padding: 12)
                }

                if !lastText.isEmpty {
                    Text(lastText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                PulseProminentButton(busy ? "记录中…" : "完成一组",
                                     systemImage: "checkmark.circle.fill") {
                    Task { await logSet(ex) }
                }
                .disabled(busy)

                if !mySets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已完成 \(mySets.count) 组")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Spacer()
                            Button("撤销上一组") { Task { await undoLast(ex) } }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.9))
                        }
                        ForEach(mySets) { s in
                            HStack(spacing: 8) {
                                Text("组 \(s.order)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PulseDesign.labelSecondary)
                                Text("\(weightText(s.weightKg)) × \(s.reps) 次")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pulseCard(padding: 14)
                }

                Button("结束锻炼") { confirmEnd = true }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .sheet(isPresented: $editingWeight) {
            NumericPadView(title: "重量", unit: "kg", initial: weight,
                           maxValue: 999, allowsHalf: true) { weight = $0 }
        }
        .sheet(isPresented: $editingReps) {
            NumericPadView(title: "次数", unit: "次", initial: Double(reps),
                           maxValue: 999, allowsHalf: false) { reps = $0 }
        }
    }

    // MARK: - 数据

    private func loadExerciseDefaults(_ ex: ExercisePickerView.Pick) async {
        if let last = await SetLogger.shared.lastSet(of: ex.id) {
            weight = last.weightKg > 0 ? last.weightKg : weight
            reps = Double(last.reps)
            lastText = "上次：\(weightText(last.weightKg)) × \(last.reps)"
        } else {
            lastText = ""
        }
        suggestion = await SetLogger.shared.progressiveSuggestion(exerciseID: ex.id, targetReps: 10)
        if let s = suggestion {
            lastText += " ｜ 建议加重到 \(weightText(s))"
        }
        await refresh()
    }

    private func logSet(_ ex: ExercisePickerView.Pick) async {
        busy = true
        let restSec = RestRules.recommended(exerciseID: ex.id, muscleGroup: ex.muscle,
                                            weightKg: weight)
        let order = await TrainingService.shared.logSet(workoutID: workoutID, exerciseID: ex.id,
                                                        reps: Int(reps), weightKg: weight,
                                                        restSec: restSec)
        busy = false
        await refresh()
        rest = RestConfig(exerciseName: ex.name, sec: restSec,
                          nextSetText: "第 \(order + 1) 组 · \(weightText(weight)) × \(Int(reps))")
    }

    private func undoLast(_ ex: ExercisePickerView.Pick) async {
        guard let last = mySets.last else { return }
        await TrainingService.shared.deleteSet(workoutID: workoutID,
                                               exerciseID: ex.id, order: last.order)
        await refresh()
    }

    private func refresh() async {
        let all = await TrainingService.shared.sessionSets(workoutID: workoutID)
        sessionTotalSets = all.count
        if let sel = selected {
            mySets = all.filter { $0.exerciseID == sel.id }
        } else {
            mySets = []
        }
    }

    private func weightText(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fkg", w)
            : String(format: "%.1fkg", w)
    }
}

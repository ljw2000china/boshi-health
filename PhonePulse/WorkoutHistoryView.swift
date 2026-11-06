import SwiftUI

/// 训练历史：会话列表 + 会话详情（编辑/补记组次）
struct WorkoutHistoryView: View {

    @State private var sessions: [TrainingService.SessionSummary] = []
    @State private var error = ""
    @State private var createdID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                PulseProminentButton("添加训练记录", systemImage: "plus.circle.fill") {
                    Task { await addManual() }
                }
                .padding(.top, 4)

                if sessions.isEmpty {
                    Text("暂无训练记录")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                ForEach(sessions) { s in
                    SwipeActionsRow(onDelete: {
                        Task {
                            await TrainingService.shared.deleteSession(s.id)
                            await refresh()
                        }
                    }, corner: 18) {
                        NavigationLink {
                            WorkoutSessionDetail(sessionID: s.id)
                        } label: {
                            sessionCard(s)
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                await TrainingService.shared.deleteSession(s.id)
                                await refresh()
                            }
                        } label: { Label("删除记录", systemImage: "trash") }
                    }
                }

                if !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(PulseDesign.labelSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedSurface()
        .navigationTitle("训练历史")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $createdID) { id in
            WorkoutSessionDetail(sessionID: id)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func sessionCard(_ s: TrainingService.SessionSummary) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(emoji(for: s.focus.title))
                    .font(.system(size: 24))
            }
            .frame(width: 46, height: 46)
            .background(PulseDesign.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(s.focus.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(s.exerciseNames.prefix(3).joined(separator: "、"))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
                    .lineLimit(1)
                Text(shortDay(s.dayKey))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.totalSets)")
                    .font(PulseDesign.bigNumber(20))
                Text("组")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PulseDesign.labelTertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .modifier(GlassCardFill(opacity: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func emoji(for title: String) -> String {
        if title.contains("胸") { return "💪" }
        if title.contains("背") { return "🦅" }
        if title.contains("腿") { return "🦵" }
        if title.contains("肩") { return "🤸" }
        if title.contains("臂") { return "🦾" }
        if title.contains("核心") { return "🌀" }
        if title.contains("休息") { return "😴" }
        return "🏋️"
    }

    private func shortDay(_ dayKey: String) -> String {
        // dayKey: yyyy-MM-dd
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3 else { return dayKey }
        return "\(parts[1])月\(parts[2])日"
    }

    private func addManual() async {
        let now = Date()
        let w = await TrainingService.shared.createManualSession(
            dayKey: TrainingSummary.dayKey(for: now), start: now, end: now)
        createdID = w.id
        await refresh()
    }

    private func refresh() async {
        sessions = await TrainingService.shared.recentSessions()
    }
}

/// 会话详情：按动作列组次，可改重量/次数、删除、补记、加动作
struct WorkoutSessionDetail: View {

    let sessionID: String
    @State private var summary: TrainingSummary.DaySummary?
    @State private var editSet: TrainingSummary.TrainingSet?
    @State private var showDateChange = false
    @State private var confirmDeleteSession = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let s = summary {
                    totalCard(s)

                    if s.isEmpty {
                        Text("还没有组次记录，点下方「记一组」开始。")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PulseDesign.labelSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    ForEach(s.exerciseOrder, id: \.self) { exID in
                        exerciseCard(s, exID: exID)
                    }

                    NavigationLink {
                        ExercisePickerView { pick in
                            Task {
                                await TrainingService.shared.logSet(workoutID: sessionID,
                                                                    exerciseID: pick.id,
                                                                    reps: 10, weightKg: 20)
                                await refresh()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("补记一组（选动作）")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .foregroundStyle(PulseDesign.accent)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(PulseDesign.accent.opacity(0.6), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("训练详情")
        .navigationBarTitleDisplayMode(.inline)
        .themedSurface()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showDateChange = true } label: {
                        Label("修改日期", systemImage: "calendar")
                    }
                    Button(role: .destructive) { confirmDeleteSession = true } label: {
                        Label("删除整条记录", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(PulseDesign.accent)
                }
            }
        }
        .sheet(isPresented: $showDateChange) {
            SessionDateSheet(sessionID: sessionID,
                             initial: summary.map { $0.dayKeyDate } ?? Date()) {
                await refresh()
            }
        }
        .confirmationDialog("删除这条训练记录？组次也会一起删掉。",
                            isPresented: $confirmDeleteSession,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    await TrainingService.shared.deleteSession(sessionID)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(item: $editSet) { set in
            EditSetSheet(workoutID: sessionID, set: set) { await refresh() }
        }
    }

    private func totalCard(_ s: TrainingSummary.DaySummary) -> some View {
        HStack(spacing: 0) {
            statBlock(title: "组数", value: "\(s.totalSets)", unit: "组")
            Divider().frame(height: 36)
            statBlock(title: "总容量", value: volumeText(s.volumeKg), unit: "")
            Divider().frame(height: 36)
            statBlock(title: "动作", value: "\(s.exerciseOrder.count)", unit: "个")
        }
        .frame(maxWidth: .infinity)
        .pulseCard(padding: 14)
    }

    private func statBlock(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(PulseDesign.bigNumber(19))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseCard(_ s: TrainingSummary.DaySummary, exID: String) -> some View {
        let sets = s.sets(for: exID)
        let ex = ExerciseLibrary.exercise(id: exID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(ex?.zh ?? s.exerciseName(exID))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(sets.count) 组")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
            ForEach(sets) { set in
                SwipeActionsRow(onEdit: {
                    editSet = set
                }, onDelete: {
                    Task {
                        await TrainingService.shared.deleteSet(workoutID: sessionID,
                                                               exerciseID: exID, order: set.order)
                        await refresh()
                    }
                }) {
                    HStack(spacing: 10) {
                        Text("第\(set.order)组")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PulseDesign.labelSecondary)
                            .frame(width: 52, alignment: .leading)
                        Text("\(weightText(set.weightKg)) kg × \(set.reps)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PulseDesign.labelTertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard(padding: 14)
    }

    private func refresh() async {
        summary = await TrainingService.shared.sessionDaySummary(workoutID: sessionID)
    }

    private func weightText(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.1f", w)
    }

    private func volumeText(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1ft", v / 1000) : String(format: "%.0fkg", v)
    }
}

/// 编辑一组（手机端调整重量/次数：加减 5kg，或点数字直接输入）
struct EditSetSheet: View {

    let workoutID: String
    let set: TrainingSummary.TrainingSet
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double = 0
    @State private var reps: Double = 0
    @State private var editingWeight = false
    @State private var editingReps = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ExerciseIllustrationView(
                        muscleGroup: ExerciseLibrary.exercise(id: set.exerciseID)?.muscle ?? "力量")
                        .frame(height: 110)
                        .padding(.top, 8)

                    QuantityControl(title: "重量 kg（点数字直接输入）", value: $weight,
                                    step: 5, range: 0...999) { editingWeight = true }
                        .pulseCard(padding: 12)
                    QuantityControl(title: "次数（点数字直接输入）", value: $reps,
                                    step: 1, range: 0...999, isCount: true) { editingReps = true }
                        .pulseCard(padding: 12)

                    PulseProminentButton("保存") {
                        Task {
                            await TrainingService.shared.updateSet(workoutID: workoutID,
                                                                   exerciseID: set.exerciseID,
                                                                   order: set.order,
                                                                   reps: Int(reps), weightKg: weight)
                            await onSaved()
                            dismiss()
                        }
                    }
                    .disabled(weight <= 0)
                    .opacity(weight <= 0 ? 0.5 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .navigationTitle("第 \(set.order) 组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $editingWeight) {
                NumericPadView(title: "重量", unit: "kg", initial: weight,
                               maxValue: 999, allowsHalf: true) { weight = $0 }
            }
            .sheet(isPresented: $editingReps) {
                NumericPadView(title: "次数", unit: "次", initial: reps,
                               maxValue: 999, allowsHalf: false) { reps = $0 }
            }
        }
        .onAppear {
            weight = set.weightKg
            reps = Double(set.reps)
        }
    }
}


/// 改训练日期：DatePicker + 保存
struct SessionDateSheet: View {

    let sessionID: String
    let initial: Date
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(sessionID: String, initial: Date, onSaved: @escaping () async -> Void) {
        self.sessionID = sessionID
        self.initial = initial
        self.onSaved = onSaved
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DatePicker("训练日期", selection: $date,
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .pulseCard(padding: 12)

                Text("把这条记录挪到正确的日期，组次时间会一起平移。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)

                PulseProminentButton("保存") {
                    Task {
                        await TrainingService.shared.updateSessionDate(sessionID, newDate: date)
                        await onSaved()
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .navigationTitle("修改日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .themedSurface()
        }
    }
}

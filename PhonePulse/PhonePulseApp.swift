import SwiftUI

/// Pulse iOS App 入口：启动时触发 HealthKit 授权流程。
@main
struct PhonePulseApp: App {

    @StateObject private var theme = ThemeStore()

    @StateObject private var hk = HKService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .environmentObject(hk)
                .task {
                    await hk.requestAuthorizationIfNeeded()
                    MorningReport.requestAuthorization()
                    ExerciseLibrary.seedIfNeeded(in: PulseStore.shared)
                    await DataPipeline.shared.syncNow()
                    await DataPipeline.shared.rebuildBaseline()   // 基线：恢复/压力/准备度对照系
                    await DataPipeline.shared.ensurePipelineUpToDate()
                    await DataPipeline.shared.rebuildRecent(days: 14)  // 睡眠窗/评分：追平近两周
                    await HKSyncEngine.shared.startObservers { _ in
                        Task { await DataPipeline.shared.syncNow() }
                    }
                    WCSyncService.shared.onDailyMetricReceived = { data in
                        Task { await DataPipeline.shared.importRemoteMetric(data) }
                    }
                    WCSyncService.shared.onSetLogReceived = { data in
                        guard let dto = try? JSONDecoder().decode(SetLogDTO.self, from: data) else { return }
                        Task { await TrainingService.shared.importSetLog(dto) }
                    }
                    WCSyncService.shared.onSessionReceived = { data in
                        guard let dto = try? JSONDecoder().decode(WorkoutSessionDTO.self, from: data) else { return }
                        Task { await TrainingService.shared.importSession(dto) }
                    }
                    _ = WCSyncService.shared // 激活 WCSession
                }
        }
    }
}

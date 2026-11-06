# 非阻塞待办（nits）

> 来自各阶段评审的 PASS_WITH_NITS / 建议项，不阻塞阶段推进，里程碑空闲时处理。

## M0（2026-11-03）
### 代码评审
- [ ] README 构建示例已补 id 兜底说明（已修）；resign.sh 设备列表解析依赖 devicectl 列格式，极端设备名可能错位 → 有 DEVICE_ID 兜底，暂不处理
- [ ] HKService.requestAuthorizationIfNeeded() 失败进 .failed 后无错误留存 → 建议加 print/assertionFailure（调试期）
- [ ] HKTypeEntry.isQuantity 字段暂无人读取 → M1 用到再留，否则删
- [ ] debugSummaries() 26 条查询可 withTaskGroup 并发提速 → 非阻塞，M1 若复用此查询模式再优化
- [ ] M1 起增量同步须落 HKAnchoredObjectQuery 到 Shared/HK/；当前全量调试查询不得流出调试页

### 产品评审
- [ ] 手表「等待授权」文案写「iPhone 的健康 App」，独立手表/未配对场景会误导 → M1 按配对状态分文案
- [ ] 24h 计数改 HKStatisticsQuery 的优化建议 → 已由 limit 截断方案缓解，M1 再评估
- [ ] README 真机一节补 DEVICE_ID 环境变量说明（脚本头注释与报错信息已覆盖）
- [ ] 手表端尚未经任何运行时验证（无 watchOS 模拟器运行时）→ watchOS 26.2 模拟器下载中，装好后补一次手表模拟器运行

### 环境（2026-11-03 更新）
- [x] watchOS 26.2 模拟器运行时：首次下载失败（MobileAsset extractor 错误），重试成功安装
- [x] **结论：本机 Intel Mac 无法构建 watchOS 模拟器**（Xcode 26 平台缺陷，任何工程复现，已用 XcodeGen 生成工程对照验证）→ 手表端验证策略 = swiftc typecheck + 真机 S9
- [x] **手表为 watchOS 26.6** → Xcode 16.4 安装路线作废（仅支持 ≤11.x）；唯一路径 = Apple Silicon Mac + Xcode 26（远程构建方案已定）
- [x] 工程生成方式由手写 pbxproj 切换为 **XcodeGen**（`project.yml` → `xcodegen generate`）；原因：手写 watchapp2 pbxproj 的 lipo 冲突无法解决且维护成本高；M0 规格中“无 XcodeGen 依赖”条款由 Orchestrator 修订（见 M0.md 阶段记录）
- [x] iOS 26.3.1 模拟器运行时安装成功（PulsePhone 模拟器构建通过）
- [ ] 真机端到端安装未实测（需 S9 在线解锁 + Xcode 登录免费 Apple ID 后跑 scripts/resign.sh）

---

## M1 非阻塞 nits

- `L2Tracker` 3h 时间上限无持久化：重启后 failCount 重置，延伸窗口可能多判定一次（3h 硬上限仍生效）
- `decodeSegments` JSON 解析失败静默返回 `[]`：数据损坏时置信度计算被静默影响
- `DataPipeline` 12 处 `try?` 吞掉 SwiftData 错误，无日志
- `dayKey` 手动 String(format:)：0 年月日产非法 key（正常路径不会触发）
- `Confidence.reason` 阈值（0.7/0.8/0.8）无 design.md 出处
- 「今晚睡眠」区块不显示 L2 延伸次数（用户感知不到延伸行为，只有失败计数）

---

## M4 训练检测 nits

- `hrSignal` 缺 σ 低检查：design.md §7 要求「HR≥静息+35 且持续 4min 且 σ低(0.35)」，当前只查阈值+持续时长，偶发心率尖峰（压力/咖啡/楼梯）可能误触发。需原始 HR 序列计算滚动标准差。**TODO-M4+**
- `inferType` 无步频/位移输入：§7 要求「步频高+位移→跑步；步频低+HR高+能量高→力量」，当前用 HR/能量比近似。需 CMMotionActivity/CMPedometer。**TODO-M4+**
- `shouldEnd` 只返回 Bool：§7「通知确认 30s 无响应自动结束」交互需 WorkoutSession + UI 层补
- WorkoutWriter HKWorkout save 使用 `store.save([workout])`，需验证 iOS 18/watchOS 11 API 兼容性

## M5 组次记录 nits

- SetLogView 休息计时用 `restRemaining` 状态但无 Timer 驱动（需 SwiftUI Timer/TimelineView 补）
- 训练 tab workoutID 用 `manual_<dayKey>` 临时方案，未与 Workout @Model 关联（M7 补）

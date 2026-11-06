# M0 代码评审报告
日期：2026-11-03 / 评审范围：M0 交付物（Pulse.xcodeproj、WatchPulse/、PhonePulse/、Shared/、scripts/、README.md）/ 评审者：subagent

## 结论：PASS_WITH_NITS

**验证记录（本人实测）**：
- `xcodebuild -scheme PulsePhone -destination 'platform=iOS Simulator,id=UDID_SIM（iPhone 16, OS 18.2）' build` → **BUILD SUCCEEDED**（仅 AppIntents 元数据无害警告）。
  - 附带发现：`-destination 'name=iPhone 16'` 在本机无法匹配（xcodebuild 报 Unable to find a device），改用 id 即通过；README.md「构建」一节用 `name=iPhone 16` 的示例命令在本机不可复现，建议 README 补充「name 匹配失败时改用 id」的提示。
- PulseWatch：本机 Xcode 26.3 **未安装任何 watchOS 平台**（`xcrun simctl list runtimes` 无 watchOS；xcodebuild 报 `watchOS 26.2 is not installed`，连 device SDK 占位都报错），无法选 destination，与已知背景一致。手表端代码与手机端共享全部 Shared/ 源码，App/视图代码均为跨端 SwiftUI API（`NavigationStack`/`refreshable`/双参 `onChange` 均 watchOS 11 可用），未发现 watchOS 编译期风险点。
- `productType = "com.apple.product-type.application.watchapp2"`（pbxproj:171）已修复确认。

## 功能正确性对照

| 规格条目 | 状态 | 证据/问题 |
|---|---|---|
| 手写 minimal pbxproj，共享 schemes ×2 | ✅ | project.pbxproj 全文可读、无生成器痕迹；xcshareddata/xcschemes/PulseWatch.xcscheme:18、PulsePhone.xcscheme:18 BlueprintIdentifier 指向正确 target |
| Bundle ID / 签名 / 部署目标 | ✅ | pbxproj:225/265（`com.boshi.watch` / `.phone`）、`DEVELOPMENT_TEAM=""`、`CODE_SIGN_STYLE=Automatic`、watchOS 11.0 / iOS 18.0、`SWIFT_VERSION=5.0` |
| Entitlements 仅 HealthKit | ✅ | WatchPulse.entitlements:5-6、PhonePulse.entitlements:5-6；无 App Groups/iCloud/Push（全仓 grep 无命中） |
| Info.plist 中文 UsageDescription | ✅ | WatchPulse/Info.plist:27-28、PhonePulse/Info.plist:35-36 |
| 启动请求 §10 全部读类型 | ✅ | HKService.swift:42 `toShare: [], read: HKTypeRegistry.readTypes`；HKTypes.swift:44-69 注册 13 项，与 design.md §10 逐一比对完全一致（含 workout、exerciseTime） |
| 未授权「等待授权」+ 跳设置提示 | ✅ | 手表 DebugDataView.swift:35-49（文案指引「健康」App）；手机 DebugDataView.swift:41-55（含「打开系统设置」按钮） |
| 授权后自动刷新 | ✅ | 两端 DebugDataView `onChange(of: hk.authState)` → reload（Watch:28-31，Phone:30-32） |
| 手表行式汇总 + 下拉刷新 | ✅ | WatchPulse/DebugDataView.swift:59-83（类型/最新值/24h 计数/更新时间 + `.refreshable`） |
| 手机列表 + 点入明细（值/起止/来源） | ✅ | PhonePulse/DebugDataView.swift:96-141（`DebugSampleListView` 展示 valueText/startDate/endDate/sourceName） |
| 空数据「暂无数据」不崩溃 | ✅ | 汇总空态、行内空值、明细空态三处均有兜底（Watch:64,73；Phone:66,72,124） |
| 授权被拒/读权限不可回读的诚实表达 | ✅ | HKService.swift:5-8 注释明确说明设计；`AuthState` 不假装知道拒绝态 |
| scripts/resign.sh 骨架 + 7 天续签说明 | ⚠️ | 顶部注释完整（resign.sh:1-30），但 **watch 路径产物目录写错，见下「必须修复前的高优项」** |
| README 工程说明/构建/安装步骤 | ✅ | README.md 全文覆盖；仅 destination name 匹配一处不可复现（见上） |
| 无网络请求/无追踪 SDK | ✅ | 全仓唯一 URL 是 `UIApplication.openSettingsURLString`（PhonePulse/DebugDataView.swift:49），非网络请求 |

## 开销评估

| 项目 | 评估 | 证据 |
|---|---|---|
| CPU | 低。无主线程重计算；查询回调经 continuation 收敛，汇总 13×2 条查询顺序执行（调试页手动触发，可接受） | HKService.swift:58-75 |
| 内存 | 可控但有一个峰值点：`debugSummaries()` 为精确计数对每类做 24h **全量拉取**（`HKObjectQueryNoLimit`，HKService.swift:64）。心率 24h 在手表上可达上万条 HKSample 瞬时驻留。M0 调试页手动刷新一次可容忍，且代码注释（:63）已自证知情；建议 M1 改为上限截断（如 limit 5000，显示「≥5000」）或 `HKStatisticsQuery` 计数 | HKService.swift:63-64 |
| 存储 | 本阶段无持久化（符合 M0 非目标），仅 1 个 UserDefaults bool | HKService.swift:31,44 |
| 电量 | 无任何定时器/轮询/后台交付声明；查询仅由用户手势触发，符合 PLAN 预算 | 全仓无 `Timer`/`HKObserverQuery`/`enableBackgroundDelivery`（M0 非目标） |

## 算法评审
- 与 design.md 一致性：本阶段无评分算法（非目标）；`SampleSource` 六值枚举与 design.md §3 逐字一致（Shared/Model/SampleSource.swift:4-10）；§10 读清单与注册表完全一致（HKTypes.swift:44-69），quantity/category 不混用，`HKWorkoutType` 走独立分支（HKTypes.swift:26-28）。
- 数值稳定性：格式化路径全部先 `as?` 转型再取值，类型不匹配返回 "—" 不崩溃（HKService.swift:129-158）；`HKTypeEntry.sampleType` 的 force unwrap（HKTypes.swift:30,32）只对硬编码常量标识求值，无实际风险。无除法/窗口聚合逻辑，无除零面。
- 优化空间（具体建议）：
  1. 24h 计数改截断式计数（见内存行）。
  2. `debugSummaries()` 的 26 条查询可分批并发（`withTaskGroup`），手表上首次打开调试页延迟可从串行 ~13×RTT 降到 ~2×RTT；非阻塞。
  3. `HKTypeEntry.isQuantity` 字段目前无人读取（HKTypes.swift:16），M1 用到再留，否则删除。

## 必须修复（不阻塞 M0 验收，但须在 M1 开始前修复）
1. **scripts/resign.sh:49**：`APP_PATH` 硬编码 `Debug-iphoneos`，`./scripts/resign.sh watch` 构建出的产物在 `Debug-watchos/`，安装步骤必失败。应将 `APP_PATH` 放入 `case` 分支（watch 用 `Debug-watchos/PulseWatch.app`）。这是免费证书 7 天续签的唯一生命线脚本，不能带病进 M1。

## 建议（不阻塞）
- `xcrun devicectl device install app`（resign.sh:63）缺 `--device` 参数，多设备/首次运行会交互失败；建议补 `--device "${DEVICE_ID:?}"` 或明确文档化。
- README.md 构建示例补一句「name 匹配失败时用 `xcrun simctl list devices available` 的 id 作为 destination」（本次实测踩中）。
- `HKService.requestAuthorizationIfNeeded()` 失败进 `.failed` 后无错误信息留存，调试期建议 `assertionFailure` 或至少 `print`（HKService.swift:46-47）。
- 手表等待授权页文案指向「iPhone 的健康 App」（WatchPulse/DebugDataView.swift:39），对未配对的独立手表场景会误导；M1 可按配对状态分文案。
- M1 起涉及增量同步时，请把 checklist §2 的 `HKAnchoredObjectQuery` 落到 Shared/HK/，当前全量调试查询不要流出调试页。

## 附：M0 验收标准核对
- [x] PulsePhone 模拟器构建通过（本人实测 BUILD SUCCEEDED）
- [~] PulseWatch 构建：环境性阻塞（watchOS 平台未安装，非代码问题）；代码侧无已知编译风险
- [x] 交付物文件树与规格一致（含 `docs/review/M0-code.md` 占位空文件待本报告写入）
- [x] 无网络/App Groups/iCloud/Push
- [x] 授权清单与 design.md §10 完全一致（13 项，含 workout + exerciseTime）
- [x] 空数据/未授权 UI 状态齐备

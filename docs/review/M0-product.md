已通读全部交付物（工程文件、双端源码、Shared、脚本、README、schemes、entitlements/Info.plist），并实际验证了 `devicectl` 用法与产物目录命名规则。以下为评审报告：

---

# M0 产品评审报告
日期：2025-01（仓库现状快照） / 评审范围：M0 交付物（Pulse.xcodeproj、WatchPulse/、PhonePulse/、Shared/、scripts/、README.md） / 评审者：subagent

## 结论：REWORK

> 量规得分 14/16，App 内交付物质量良好；但触发致命项 2「主流程断裂」：**`scripts/resign.sh` 的安装步骤实际不可执行**——这是免费证书约束下用户唯一能把 App 装上真机、并在 7 天后续命的通道，属于阶段承诺路径无法走通。修复面很小（一个脚本），修复后可直接复审。

## 规格兑现对照

| 规格条目（用户可见承诺） | 状态 | 证据 |
|---|---|---|
| 手写 pbxproj，双 Target + 共享 schemes（PulseWatch/PulsePhone） | ✅ | `Pulse.xcodeproj/project.pbxproj`（objectVersion 56，纯手写 ID）；`xcshareddata/xcschemes/` 两个 scheme；`xcodebuild -list` 验证通过 |
| 签名 Automatic + `DEVELOPMENT_TEAM=""`；Bundle ID 正确 | ✅ | pbxproj buildSettings：`com.boshi.watch` / `com.boshi.phone` |
| Entitlements 仅 HealthKit，无 App Groups/iCloud/Push | ✅ | 两个 `.entitlements` 均只含 `com.apple.developer.healthkit=true`；全仓 grep 无 `application-groups`/`aps-environment`/iCloud 命中 |
| Info.plist 中文授权文案；watch 独立 App | ✅ | `WatchPulse/Info.plist`、`PhonePulse/Info.plist` 均含中文 `NSHealthShareUsageDescription`（且明确「不会上传」，契合诚实原则）；无 `WKCompanionAppBundleIdentifier` |
| 启动即请求 design.md §10 全部读类型 | ✅ | `WatchPulseApp.swift:13`、`PhonePulseApp.swift:11` `.task` 触发；`Shared/HK/HKTypes.swift:47-78` 逐项核对 13 个读类型与 §10 **完全一致**（心率/HRV/静息心率/呼吸/腕温/血氧/睡眠/步数/活动能量/站立/距离/锻炼时间/训练） |
| 未授权：调试页「等待授权」+ 跳设置提示 | ✅ | 手表 `WatchPulse/DebugDataView.swift:37-53`（文字指引去健康 App）；手机 `PhonePulse/DebugDataView.swift:42-62`（文字指引 + 「打开系统设置」按钮深链，该行 URL 仅 `openSettingsURLString`，非网络请求） |
| 授权后自动刷新 | ✅ | 两端 DebugDataView 均 `onChange(of: hk.authState)` 触发 reload |
| 手表调试页：每类一行「类型·最新值·更新时间·24h 计数」，下拉刷新 | ✅ | `WatchPulse/DebugDataView.swift:71-84` + `.refreshable` |
| 手机调试页：列表 + 点入明细（值/起止时间/来源） | ✅ | `PhonePulse/DebugDataView.swift:96-148`（DebugSampleListView 展示 valueText/起止时间/来源名） |
| 空数据显示「暂无数据」不崩溃 | ✅ | 手表 `stateMessage(icon:"tray",…)`；手机 `ContentUnavailableView("暂无数据")`；查询失败均回落空数组（`HKService.swift:104`） |
| 部署目标 watchOS 11 / iOS 18；Swift 5 模式 | ✅ | pbxproj：`WATCHOS_DEPLOYMENT_TARGET=11.0`、`IPHONEOS_DEPLOYMENT_TARGET=18.0`、`SWIFT_VERSION=5.0`，无严格并发开关 |
| 模拟器构建通过 | ⚠️ | PulsePhone 已通过（已知背景）；PulseWatch 因系统缺 watchOS 模拟器运行时仅完成 typecheck——**环境限制，非交付缺陷**，但手表端交互（TabView/列表/下拉刷新）均未经历任何运行时验证，M1 前需补 |
| resign.sh：构建 + 安装 + 7 天续签说明 | ❌ **致命** | `scripts/resign.sh:67`：`xcrun devicectl device install app --app "$APP_PATH"`——实测 `devicectl device install app --help`：app 路径是**位置参数**（无 `--app` 选项）且 `--device <id>` 为**必填**，该命令会立即报错；`:44`：`APP_PATH` 硬编码 `Debug-iphoneos`，watch scheme 产物实际在 `Debug-watchos`，`resign.sh watch` 必然找不到产物。两条安装路径均断裂 |
| README 工程说明/构建命令/真机步骤 | ✅ | `README.md` 完整，含免费证书约束与信任证书步骤 |

## 量规评分（总分 14/16）

| # | 维度 | 得分 | 证据 |
|---|---|---|---|
| 1 | 任务效率 | 2 | 手表核心路径：打开 App → 今日 Tab 点「调试数据」= 2 次交互（`WatchPulse/ContentView.swift:36-40`，设置页另有第二入口）；手机：打开 → 点「原始数据调试」= 1 次，明细再 1 次 |
| 2 | 易学性 | 2 | 全中文文案，标准 SwiftUI 列表/Tab/NavigationLink 模式；空态/等待态均有下一步指引文案，无需查资料 |
| 3 | 容错 | 2 | M0 全程只读（`requestAuthorization(toShare: [])`，`HKService.swift:47`），无任何破坏性操作；授权失败状态可一键重试（≤1 步） |
| 4 | 反馈 | 2 | 首载 `ProgressView("读取中…")`、下拉刷新有系统 spinner、授权三态（不可用/等待/已请求）均有图标+文案卡片；M0 无评分类页面，徽标要求不适用 |
| 5 | 用户习惯契合 | 2 | 零配置：首启自动弹授权（`requestAuthorizationIfNeeded` 用 UserDefaults 幂等，不重复打扰）；调试入口固定在首页，无需寻找 |
| 6 | 通知节制 | 2 | M0 无任何通知代码（grep 无 UNUserNotificationCenter 命中），默认 0 条/天 |
| 7 | 手表人体工学 | 1 | 调试页次要文字不达标：时间戳用 `.caption2`（≈11pt）、「24h ×N」与授权指引用 `.footnote`（≈13pt），均 <14pt（`WatchPulse/DebugDataView.swift:49,79,44`）；主按钮 `.borderedProminent` 高度达标。M0 规格将「UI 美化」列为非目标，故给 1 分而非 0 |
| 8 | 性能与电量 | 1 | `HKService.swift:67` 对 13 个类型各做一次 24h 全量拉取（`HKObjectQueryNoLimit`）仅为计数，心率类高频样本在手錶上可能造成秒级卡顿；代码注释已自知（`:65`「仅调试页手动刷新时执行」）属「略超预算但有说明」。冷启动无实测（手表端未跑起来） |

## 双角色动线走查
- **早起动线 / 健身动线**：M0 非目标（恢复/睡眠/训练功能均未承诺），不走查。降级走查本阶段唯一动线 **「首启 → 授权 → 查看调试数据」**：
  - 顺畅点：启动即弹授权零配置；授权完成页面自动刷新；空数据/无数据均有明确中文状态；手机端可一层层点到单条样本的来源与起止时间。
  - 别扭点：① 用户在系统弹窗里拒绝后，「重新请求授权」按钮静默无效（HealthKit 不会二次弹窗）——虽然有文字指引去健康 App，但按钮本身无任何反馈说明「为什么没反应」（`HKService.swift` 状态机无法区分「未请求」与「已拒绝」，属系统限制，文案可再诚实一点）。② 手表端全程未真机/模拟器运行过，上述顺畅点目前只是代码推演。

## 必须修复（REWORK 时）
1. **`scripts/resign.sh` 安装步骤修复**（`scripts/resign.sh:44, 63-74`）：
   - `devicectl device install app` 改为位置参数传 app 路径，并增加 `--device` 必填参数（或从 `xcrun devicectl list devices` 交互选择/读 `DEVICE_ID` 环境变量）；
   - `APP_PATH` 按 scheme 区分产物目录：phone → `Debug-iphoneos`，watch → `Debug-watchos`；
   - 修复后用真实命令自证（哪怕只到 `devicectl` 报「无设备连接」为止），把验证输出附进交付汇报。

## UI 优化建议（不阻塞）
- 手表调试页把 `.caption2`/`.footnote` 提升到 ≥14pt（或 `.footnote` 起步），为 M1 的 14pt 规范提前打底。
- 授权被拒场景：按钮点击后若无系统弹窗，补一行「系统不再弹出授权框，请按上方指引手动开启」的即时说明，避免用户反复点。
- 24h 计数改用 `HKStatisticsQuery`/count 语义，避免全量样本拉取（也可留给代码评审决定）。
- 两个 Target 的 AppIcon 均为空槽（`AppIcon.appiconset/Contents.json` 无 filename），真机安装后为空白图标，建议 M1 前补一张占位图。
- 手表「等待授权」文案提到「请在 iPhone 的健康 App…」，但首启授权其实可在手表弹窗内完成；区分「未请求」与「已请求被拒」两种文案会更诚实。

## 无感程度评价
- **已经无感的部分**：授权请求首启自动触发且幂等不重复打扰；授权后数据自动出现；空态诚实显示「暂无数据」而非编造；零通知、零网络、零写入——本阶段完全符合「安静」「诚实」原则。
- **仍打扰/有摩擦的部分**：最大的一处不在 App 内而在安装链路——resign.sh 断裂意味着用户每 7 天的续签会变成「手动排错 shell 脚本」，这与产品原则 1「用户无感」直接冲突，故判 REWORK。其次，授权被拒后的按钮静默无效是一处小摩擦；手表端未经任何运行时验证，当前的无感程度结论需待 M1 真机链路打通后复核。

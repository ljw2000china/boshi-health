# DutyShift → 个人健康监测 App — 总计划 v2

> 自用 · Apple Watch S9 + iPhone · 端侧计算 · 无服务器
> 状态：待启动（M0 前需用户最终确认）

---

## 1. 决策锁定（2024-11 评审通过）

| # | 决策点 | 结论 |
|---|---|---|
| D1 | 训练自动开始方式 | **静默开始**（置信度 ≥0.8 直接起会话，事后通知可改类型/取消） |
| D2 | 睡眠延伸确认通知 | **不要**，静默判定 + 事后手动修正 |
| D3 | 睡眠修正交互 | 手表端拖动 + **iPhone 端精细时间轴拖动**（5 分钟精度） |
| D4 | 力量训练组次记录 | **要**：动作库 + 组次/重量 + 模板 + 手表快速记组 + 休息计时 |
| D5 | HealthKit 写回 | **训练写回**（进系统健身记录）；睡眠**不写回** |
| D6 | Recovery 权重用户可调 | 暂不做（固定权重） |
| D7 | 主观反馈 | **要**：每日精力/酸痛 1–5 打卡，纳入 Recovery（小权重）与趋势 |

### 范围更新（相对 v1 设计）
- **iPhone 端从“重展示”升级为真正的伴侣 App**：手动补录训练（无法识别的动作）、编辑组次、睡眠时间轴修正、图表、周报、导出、设置。
- 新增模块：**训练组次系统**（动作库 ~60 个常用动作、 routines 模板、手表记组、休息计时、上次同动作参考、简单渐进建议）。

---

## 2. Subagent 执行体系

### 角色
| 角色 | 由谁承担 | 职责 |
|---|---|---|
| **Orchestrator** | 主会话（我） | 写阶段规格 → 派发执行者 → 验证构建 → 派发评审 → 把关归档 → 向用户汇报 |
| **执行者 Executor** | `pi -p` 无头子代理（每阶段一个） | 按阶段规格实现代码/文档，自检后提交 |
| **代码评审** | `pi -p` 只读子代理（工具锁死 `read,bash`） | 功能正确性、可实现性、实现方式合理性、硬件/软件开销（CPU/内存/电量/存储）、算法优化空间 |
| **产品评审** | `pi -p` 只读子代理（工具锁死 `read,bash`） | 可用性、UI、便利性：功能尽量用户无感；手表快速查看、手机充分编辑；按 `docs/review/rubric.md` 评分 |
| **用户** | 你 | 阶段门禁的最终裁决人；可随时叫停 |

### 工作流（每个阶段）
```
1. Orchestrator 写 docs/phases/Mx.md（阶段规格：目标/输入/交付物/验收标准）
2. 派发执行者：
   pi -p --no-session --append-system-prompt @docs/agents/executor.md \
        @docs/phases/Mx.md "执行本阶段并输出交付物清单与自检结果"
3. Orchestrator 验证：编译 / 测试 / 交付物完整性
4a. 派发产品评审（只读）：
   pi -p --no-session -t read,bash --append-system-prompt @docs/agents/product-reviewer.md \
        @docs/review/rubric.md @docs/phases/Mx.md "审查当前仓库交付物，输出产品评审报告"
4b. 派发代码评审（只读）：
   pi -p --no-session -t read,bash --append-system-prompt @docs/agents/code-reviewer.md \
        @docs/review/code-checklist.md @docs/phases/Mx.md "审查当前仓库交付物，输出代码评审报告"
5. 报告归档 docs/review/Mx-product.md 与 Mx-code.md，两份独立判定：
   - 两份均 PASS → 进入下一阶段
   - 任一份 REWORK → 执行者修复 → 双重复审（最多 2 轮，仍不过则升级给用户）
   - PASS_WITH_NITS → 记入 docs/nits.md 待办，不阻塞
6. 每阶段结束向用户汇报：交付摘要 + 评审结论 + 关键问题
```

### 评审量规（核心：可用性 / 便利性 / 用户习惯）
见 `docs/review/rubric.md`，量化标准摘要：

| 维度 | 关键标准（举例） |
|---|---|
| 任务效率 | 手表记一组 ≤3 次交互；核心任务单手完成 |
| 易学性 | 无说明书完成首次核心任务；遵循 Apple HIG 隐喻（圆环/列表/浮层） |
| 容错 | 撤销/修改 ≤2 步；破坏性操作必须二次确认 |
| 反馈 | 每个操作即时触觉/视觉反馈；数据不足明示原因 |
| 用户习惯契合 | 默认路径零配置可用；重复操作有快捷方式（复用上一组/模板）；默认通知 ≤2 条/天 |
| 手表人体工学 | 次要文字 ≥14pt；主按钮 ≥44pt；3 秒内可读主信息；深色对比合格 |
| iPhone 体验 | 时间轴拖动 5min 精度；编辑表单不滚动超过 1 屏 |
| 性能/电量 | 冷启动 <2s；单阶段新增耗电在预算内 |

评分 0–2/项，≥85% 且无致命项判 PASS；致命项（数据损坏风险 / 主流程断裂 / 安全）一票 REWORK。

---

## 3. 阶段计划

| 阶段 | 目标 | 主要交付物 | 依赖 | 预估 |
|---|---|---|---|---|
| **M0** | 工程骨架 | watchOS+iOS 双 Target、HealthKit 授权流程、原始数据调试页、SwiftData 骨架 | ✅ 完成 |
| **M1** | 数据管道 + 睡眠窗口 | ObserverQuery/AnchorQuery、SleepWindow L1/L2/L4、Confidence | ✅ 完成 |
| **M2** | 评分引擎 + 总览 | Baseline(28d)、Recovery/SleepScore/Strain/ACWR/SleepDebt、今日概览 | ✅ 完成 |
| **M3** | 打卡 + 晨报 | 精力/酸痛 1–5、晨报通知、Recovery 纳入打卡项 + WCSession 双端同步 | ✅ 完成 |
| **M4** | 训练自动识别 | 检测信号引擎、静默起会话（≥0.8）、类型推断、结束检测、HKWorkout 写回 | ✅ 完成 |
| **M5** | 组次系统 | 动作库(~60)、手表快速记组（≤3 交互）、休息计时、渐进建议、iPhone 端 UI | ✅ 完成 |
| **M6** | 训练分析 | 区间分布、TRIMP、HRR60、训练详情页 | ⬜ M6 |
| **M7** | iPhone 伴侣端 | 睡眠时间轴修正、图表、周报、设置中心 | ⬜ M7 |
| **M8** | 表盘 + 打磨 | 3 种复杂功能、趋势页、真机长测 | ⬜ M8 |

### 电量预算（全程约束）
- 后台交付/聚合：可忽略
- 每日 1 次训练会话（~1.5h）：约 6–8%
- 睡眠延伸判定（窗口后 3h）：可忽略
- 红线：日常使用（含一次训练）24h 剩余电量 ≥20%

---

## 4. 仓库结构

```
applewatch/
├── PLAN.md                  ← 本文件（总计划）
├── docs/
│   ├── agents/
│   │   ├── executor.md      ← 执行者系统提示词
│   │   └── reviewer.md      ← 评审者系统提示词
│   ├── review/
│   │   ├── rubric.md        ← 评审量规
│   │   ├── REVIEW-template.md
│   │   └── Mx-review.md     ← 各阶段评审报告（生成）
│   ├── phases/
│   │   └── Mx.md            ← 各阶段规格（逐阶段生成）
│   └── design.md            ← 设计定稿（指标公式/算法/数据模型）
├── WatchApp/                ← watchOS App（M0 起）
├── PhoneApp/                ← iOS 伴侣 App（M0 起骨架，M7 充实）
└── Shared/                  ← 共享模型/算法（Swift Package）
```

---

## 5. 启动检查单

- [x] 用户确认本计划（双评审制）
- [ ] **免费证书自签**（无开发者账号）：7 天有效期，scripts/resign.sh 重签重装；约束：无 App Groups → 同步走 WCSession；HealthKit 免费证书可用
- [x] Xcode 26.3、watchOS SDK 26.2 就绪

**执行顺序（已启动）：design.md 定稿 → M0 规格 → M0 执行者 → 产品+代码双评审 → 汇报用户。**

---

## 6. 2026-11-05 可用性修复轮（睡眠/记组/图表）

**用户反馈**：① 无睡眠数据（要求 24h 自动识别，不依赖系统分期）② 记组界面残缺（无退出、无数字显示、溢出）③ 无图表。

**改动**：
- [x] `Shared/Sleep/SleepInference.swift`（新增）：L0 活动信号推测。10 分钟槽 ×（步数≤20 且 无站立 且 能量≤2kcal 且 佩戴）→ 静止段；两侧段均 ≥30min 且活动空档 ≤20min 才合并（起夜容忍）；≥30min 段保留（含午睡）；效率固定 0.92，置信度沿用 SleepWindowBuilder 公式。
- [x] `DataPipeline.rebuildNight`：L1 为空时走 L0；窗口带来源标记（system/inferred）；系统分期优先于推测；同日双端不互覆盖；推断范围 ±6h 防跨零点截断。
- [x] `Shared/UI/TrendCharts.swift` + `TrendsView.swift`（新增）：恢复趋势线、睡眠时长柱状、Strain 柱状、睡眠分期时间轴/堆叠条/图例；缺失数据断点不插值；双端共用。
- [x] `SetLogView` 重写：自定义加减行（28pt 大数字）、可换动作、可结束训练、撤销最近一组、休息计时条、建议重量。
- [x] 自检修复：`HKSyncEngine` 首次全量回填拆分为按类型 backfillDays（心率 3 天防内存尖峰）；workout 的 RawSample 从存 duration 改为存 kcal（Strain 需 kcal）；`ensurePipelineUpToDate()` 管道版本补算（老用户装新版本后自动重算 14 天，否则 L0 不生效）；SleepDebugSection/TrendsView 来源文案。
- [x] 新增 `SleepInferenceTests`（9 项），全量测试 83/83 通过。

**构建状态**：iOS 真机包已构建（build/Build/Products/Debug-iphoneos/PulsePhone.app，已签名）；watchOS 代码编译通过（generic），真机包因手表锁定未能构建——解锁手表后运行 `./scripts/resign.sh watch`。**未安装**（按用户要求）。

### 睡眠回写健康（用户请求，2026-11-05 下午）

- [x] `Shared/HK/SleepWriteback.swift`（新增，仅手表侧编译）：推测窗口回写 HKCategoryType.sleepAnalysis。规则：只写推测来源窗口；写入前查健康内是否已有非 Pulse 睡眠样本（有则跳过）；用 HKMetadataKeySyncIdentifier+version 幂等替换；系统分期出现后自动删除我们的回写（让位原生）；L2 延伸后更新回写；已写版本记录避免每次查健康。
- [x] `HKSyncEngine`：读回时丢弃 Pulse 自己写回的睡眠样本（防「推测→写回→被当系统分期」反馈环）。
- [x] `HKTypeRegistry.writeTypes`：手表侧加入睡眠分析。
- [x] `HKService.requestAuthorizationIfNeeded`：改为每启动都请求（授权增量幂等，否则老用户拿不到新增睡眠写权限）。
- [x] 手表「设置」新增「睡眠同步到健康」开关（默认开），打开时重算最近 7 天补写。
- [x] 手表 `NSHealthUpdateUsageDescription` 更新（覆盖睡眠回写）。
- [x] 全量测试 83/83；双端编译通过；iOS 真机包已构建。**watch 真机包未构建**（隧道断开/手表未解锁），解锁后 `./scripts/resign.sh watch`。
- 设计：回写仅手表侧（数据源地），避免双端重复样本；手机通过 iCloud 健康同步看到手表写入的睡眠。

### 训练流程重构（2026-11-05 晚，用户三合一需求）

- [x] `RestRules`：组间休息按 动作类型×肌群（复合 180–210s / 孤立 60–120s，≥100kg +30s，≥150kg +60s）
- [x] `TrainingSummary`：纯计算（练X日命名、周汇总/对比、动作进步曲线 PB+维持天数、Epley 1RM）
- [x] `TrainingService`：会话状态机（start/end/discard）、组 CRUD、汇总查询；组次 WCSession 实时同步（信封协议 同步类型扩展）
- [x] UI：`WorkoutControls`（大数字+小数字分量，修复小数截断）、`RestTimerView`（全屏环+跑步小人+提前结束）、`TrainingSessionView`（选动作→记组→休息 流程）、`TrainingHomeView`（练X日 banner + 今日总结）、`BodyMapView`（正/背面人体图变红）、`WeeklySummaryView`（本周 vs 上周）、`ExerciseProgressView`（曲线+突破记录）
- [x] 手机：`WorkoutHistoryView`（历史/补记/编辑组次）、主页新增 训练/本周总结/进步曲线/训练历史 入口
- [x] 删旧 SetLogView；测试 97/97；双端真机构建+安装+启动
- 注：首次手机端启动（旧 SwiftData 增加 Workout.isActive 字段）自动 lightweight migration

### 表盘小组件 + 重量精度（2026-11-05 晚 2）

- [x] 重量步进 2.5kg → **1kg**（手表记组 + 手机编辑）
- [x] `TrainingDaySnapshot`：纯逻辑（练X日/休息日 + 表情映射，测试 4 个）
- [x] `StrengthWorkoutWriter`（仅手表）：手动力量会话结束后回写 HKWorkout（肌群元数据 `PulseMuscleGroups`），watch 前台时补写最近 7 天
- [x] `PulseWidget` 小组件目标（表盘可选：横向满宽 / 圆形 / 内联），圆润字体，emoji：胸💪 背🦅 腿🦵 肩🤸 臂🦾 核心🌀 力量🏋️ 休息😴；数据源 = HealthKit 今日训练
- [x] 测试 101/101；watch+phone 真机构建安装启动
- [ ] **阻塞**：widget 扩展需新建 provisioning profile（新 bundle id），Xcode 账号会话已失效（xcodebuild 报 No Accounts）。代码/Info.plist/entitlements 已就绪，project.yml 中目标已暂时注释；待用户在 Xcode → Settings → Accounts 登录后取消注释并重建。

### 手机端重构（2026-11-05 晚 3）

- [x] App 显示名 → **薄**（Phone + Watch Info.plist CFBundleDisplayName），导航标题同步
- [x] App 图标：`scripts/make_icon.swift` 用 CoreGraphics 生成 1024 Q 版薄肌男（V 型躯干/腹肌/双肱二头肌/笑脸 + 橙粉渐变），写入两端 AppIcon
- [x] `Shared/UI/DesignSystem.swift`：PulseDesign（accent/accent2/mint、mainGradient、bigNumber）、`pulseCard()`、`PulseProminentButton`、`PulseSecondaryButton`、`PulseLinkCard`
- [x] `NumericPadView`：点按数字直接输入 0–999（含 .5 开关），自定义数字键盘，宽松布局
- [x] `QuantityControl`：数字可点击（pencil 提示）+ 48pt ± 按钮；重量步进 **5kg**、次数 1
- [x] `ExerciseIllustrationView`：按肌群手绘 Q 版姿态（胸推/背拉/腿蹲/肩平举/臂弯举/核心平板/有氧跑），Canvas 绘制、离线无图片
- [x] 记组页重排：示意图 → 重量卡 → 次数卡 → 完成一组（渐变主按钮）→ 组列表卡 → 结束锻炼，间距 16/18
- [x] 训练主页 / 本周总结 / 进步曲线（PB 卡 + AreaMark 渐变曲线 + 奖杯记录 + 横向动作胶囊）/ 训练历史（卡片列表 + 详细统计卡 + 补记按钮 + 长按删除）/ 编辑组 sheet 全部改用设计系统
- [x] 手机首页：渐变「开始训练」大卡 + 5 个 PulseLinkCard 入口
- [x] `ExerciseLibrary.exercise(id:)`：轻量查名/肌群兜底
- [x] 测试 104/104；iOS 真机包构建成功（未安装，等指示）；watchOS generic 构建成功（未安装，手表电量低）

### 双页 + 睡眠修复 + 低延迟（2026-11-05 晚 4）

- [x] 手机改 TabView：**睡眠**（概览/趋势/打卡/授权）+ **健身**（练X日 + 居中大圆按钮 + 本周总结/进步曲线/训练历史）
- [x] 大圆按钮 188pt 渐变 + 呼吸光环，`contentShape(Circle())` 整圆可点
- [x] `PulseLinkCard` 点击区修复：背景与 contentShape 移入 label 内（整卡可点，不再只点字）
- [x] 睡眠空态诊断卡：`SleepDiagnostics`（睡眠/步数/能量/心率/RHR/HRV 的最近样本 + 7 天计数）+「修复：重新授权并重拉数据」→ `DataPipeline.forceRebuild(60)`
- [x] `HKSyncEngine.resyncAll()`：清 anchor 强制回填（修「授权前 anchor 已推进 → 历史数据永久跳过」）
- [x] 低延迟：`TrainingService` 内存缓存（day/week + 动作查表，写操作失效，30s TTL）；`DataPipeline` 缓存（overview / metricHistory(days)，ingest/rebuild 失效）
- [x] 测试 104/104；iOS 真机构建 + 安装成功（启动被锁屏拦住）

### 主题系统 + 设置页 + 睡眠诊断日志（2026-11-05 晚 5）

- [x] `ThemeStore`（@AppStorage）：背景 7 种（极光/落日/海洋/薄荷/暗夜/单色/照片）+ 卡片透明度滑杆（0.02–0.6）+ 标题字体 3 种（圆润/经典/极简）；照片壁纸存 Documents/pulse_wallpaper.jpg，`scaledToFill` 自适应铺满
- [x] `PageTitleBar`：标题居中胶囊（ultraThinMaterial + 渐变描边 + 渐变字），睡眠/健身/设置三页 toolbar principal 使用
- [x] 第三页 **设置**（齿轮 Tab）：外观 / 数据 / 关于 三类；数据含健康授权状态、修复重拉、睡眠管线诊断表（逐日：样本→分段→L0→窗口）
- [x] `pulseCard`/`PulseLinkCard` 接入 `EnvironmentValues.pulseCardOpacity`，Root 注入 theme.cardOpacity
- [x] 卡顿缓存保留（TrainingService + DataPipeline 30s TTL）
- [x] **睡眠空根因定位**：导出手机 App 容器数据库 → `ZRAWSAMPLE` 0 行（心率/步数也都没有）→ HealthKit 查询全部返回空 → 授权层问题，不是管线逻辑
- [x] `PulseLog` 文件日志 + 同步每类型计数/错误埋点 + 授权后即时验证（sleep7d/steps7d）→ 设置页「同步日志」可查看/复制
- [x] 测试 104/104；iOS 真机构建安装成功（Locked 未启动）

### 睡眠空根因修复 + 毛玻璃 Q 弹卡片 + 背景穿透（2026-11-06）

- [x] **根因定位**：从手机数据库导出 → ZRAWSAMPLE=0 但日志显示 ingest 了 594+6000+ 样本 → `DataPipeline.ingest()` 构造 `RawSample(...)` 后**漏了 `ctx.insert()`**（全项目所有 SwiftData 模型创建都显式 insert，唯独此处遗漏）→ `save()` 空操作 → 健康数据从未落库 → 睡眠窗/评分全空
- [x] **修复**：ingest 中加 `ctx.insert(r)` + 落库日志 `ingest saved=N to DB`
- [x] **卡片毛玻璃 Q 弹**：`PulseCard`/`GlassCardFill` 重写 → `.ultraThinMaterial` + 顶部高光渐变 + 渐变描边 + 柔和阴影 + 22pt continuous 圆角；`PulseBouncyStyle` 按下缩放 0.96 弹簧动画；按钮/卡片统一高级感
- [x] **背景穿透**：TabView `.toolbarBackground(.hidden, for: .tabBar)` + `.background(Color.clear)`；ScrollView `.scrollContentBackground(.hidden)`；OverviewView 卡片从 `.secondarySystemBackground` 改毛玻璃
- [x] 测试 104/104；iOS 真机安装成功（Locked 待解锁验证）

## 2026-11-06 背景穿透根因 / 空指标 / 指标说明

- **背景不生效根因**（模拟器逐层像素验证）：
  1. `ThemeStore` 用 `@AppStorage`，但它在 `ObservableObject` 里**不会触发 objectWillChange** → 设置改动界面永不重绘。改为 `@Published` + `didSet` 手动写 UserDefaults。
  2. `NavigationStack` 自带**不透明底层**，画在它外面的任何背景（含红色探针）都不可见。验证：把背景加到页面 `ScrollView` 内部后，像素从 (204,204,204) 灰变为暗夜渐变 (22,21,37)→(42,33,65)。
  3. 修复：新增 `themedSurface()`（`ThemedSurfaceModifier`，`content.background(ThemeBackgroundView().ignoresSafeArea())`），铺到**所有页面的 ScrollView/VStack 根**：睡眠/健身/设置/趋势/训练历史/本周总结/进步曲线/训练首页/训练会话/选动作/打卡/调试数据/日志。
  4. 用**自定义底部毛玻璃胶囊导航**替换 `TabView`（彻底避开 UITabBarController 的不透明底层），三页并存按 opacity 显隐保留导航状态。
- **恢复/压力/准备度为空的根因**：基线（`Baseline`）只在 `OverviewView` 下拉刷新时重建，启动流程从不建 → 打分缺对照系。修复：`forceRebuild()` 增加 `rebuildBaseline()`；启动 `.task` 增加 `rebuildBaseline()`。
- **指标说明**：睡眠页新增「指标说明」卡（恢复/睡眠分/Strain/压力/睡眠债/准备度/ACWR 的定义、量程、判读）。
- **趋势页空态**：全部点为空时给出原因说明，并自动补一次 `rebuildBaseline + rebuildRecent(14)`。
- watchOS 根补 `environmentObject(theme)`（共享视图用了 themedSurface，避免运行时缺环境对象）。
- 测试 104/104 通过；模拟器验证背景生效；真机安装待设备连接。

## 2026-11-06 训练历史可编辑 / 滑动操作

- 新增 `Shared/UI/SwipeActionsRow.swift`：自定义滑动手势行
  - 向左滑露出「编辑(强调色) / 删除(红)」按钮，**按钮上下占满行高**（宽 92pt）
  - 右滑：`raw/(raw+60)*26` 渐近阻尼，最多位移 26pt，越滑越少，松手回弹
  - 越过按钮区后再左滑进入强阻尼（0.12 系数），不会无限拉出
  - 用 `predictedEndTranslation` 预测终点提升手感；打开态点击内容自动收起
- 训练历史：会话行左滑删除（保留右键菜单）；会话详情组次行左滑 = 编辑 / 删除
- 会话详情工具栏「⋯」：**修改日期**（图形日历，组次时间整体平移 `TrainingService.updateSessionDate`）、**删除整条记录**（二次确认后 pop）
- `TrainingSummary.DaySummary.dayKeyDate`：dayKey → 当天中午，用于日期回显
- 测试 104/104；iPhone（iPhone 15 Pro Max）与 Apple Watch S9 均已安装最新版

## 2026-11-06 手表归位 / 数据完整性 / 玻璃统一 / 休息日动画

- **手表**：训练移到第一页；App 名 Pulse → 薄士；启动补 `rebuildBaseline()` + `rebuildRecent(14)`（睡眠/ACWR/恢复完整）
- **手机**：启动补 `rebuildRecent(14)`，让睡眠时长/训练负荷趋势追平近两周
- **玻璃统一**：`ChartCard`、训练历史会话卡、会话行卡片改用 `GlassCardFill` 毛玻璃，去掉 `secondarySystemBackground` 实底
- **训练文本省略号**：训练主页标题 watch 版 28→22pt；练习行改为 `lineLimit(0)`+可换行+`minimumScaleFactor`，计数/最佳重固定尺寸
- **Strain 柱**：0 值不再近隐形（min 0.4 高 + 按强度调不透明度）
- **休息日横幅动画** `RestDayBannerView`：点按后表情放大并右→左→右跑马灯，滚动到文字处用 mask 逐段擦除/重显（回程重新显示），整卡上下震动（50ms 步进、幅度衰减、1.5s 渐停），结束回缩并随机换一句新梗（池：12 条休息日文案）
- 测试 104/104；iPhone & Watch 均已安装

## 2026-11-06 休息日横幅动画 v2（手机+手表统一）

- **手机也加横幅动画**：`TrainingHomeView.focusBanner` 共享文件，休息日时手机和手表都用 `RestDayBannerView`
- **手表表情不显示根因**：旧版 `emojiX` 静止时就在 +85pt → 被 `.clipShape` 裁出框外（手表屏窄，彻底裁掉）
- **重写 `RestDayBannerView`**：
  - 表情静止在右侧（`ZStack` + `alignment: .trailing`），点按放大 1.25×
  - **2.5s 线性**滚到 `-(全宽+表情)` 彻底出左框 → **停 0.5s** → **2.5s** 滚回原位
  - 文字 mask 用 trailing 宽度驱动：表情滚到哪擦到哪，回程逐段重显
  - 整卡上下震动：60ms 步进、振幅 3→2→1→0 衰减，约 5s 渐停
  - 结束后表情回缩、随机换一句新梗（12 条池）
- 双端编译通过；iPhone 已装、Apple Watch 已装

# 设计定稿 v1（所有阶段的契约）

## 1. 产品原则
1. **用户无感**：能自动的绝不让人点；必须人做的 ≤3 次交互。
2. **手表 = 快速查看 + 一键操作**：3 秒内读到主信息；复杂操作留给手机。
3. **手机 = 充分编辑**：修正/补录/配置完整可做，不打扰手表数据流。
4. **零配置起步**：首次打开即可用，高级选项进设置。
5. **诚实**：数据不足就说不足，不猜不编。
6. **安静**：默认通知 ≤2 条/天。

## 2. 平台约束（免费证书，无开发者账号）
- 7 天签名有效期 → `scripts/resign.sh` 重签重装（用户手动跑一次即可）
- **无 App Groups** → 手表/手机同步走 `WCSession`（applicationContext + 文件传输）
- 无推送 → 全部本地通知（UNUserNotificationCenter）
- 无 iCloud → 无云端备份，导出文件用户自行保管
- HealthKit 读写：免费证书可用
- 禁止：网络请求、第三方 SDK、账号体系

## 3. 架构
```
Pulse.xcodeproj（手写 minimal pbxproj，自动生成签名）
├── Target: PulseWatch (watchOS App, watchOS 11+, 单 Target 无 Extension)
├── Target: PulsePhone (iOS App, iOS 18+)
└── Shared/                ← 纯 Swift 源码，同时加入两个 Target 的编译源
    ├── HK/                ← HealthKit 读写、类型注册、后台交付
    ├── Model/             ← SwiftData 模型 + 纯值模型
    ├── Engine/            ← 基线/评分/睡眠窗口/训练识别（纯逻辑，可单测）
    └── Sync/              ← WCSession 编解码
```

数据来源枚举（所有写入必须标记）：
```swift
enum SampleSource: String, Codable {
    case system     // HealthKit 系统采集
    case extended   // App 延伸判定
    case override   // 用户手动修正
    case auto       // 自动检测产生（训练）
    case manual     // 用户手动记录
    case native     // 系统健身 App 产生（只读引用）
}
```

## 4. 数据模型（SwiftData）
| 模型 | 关键字段 | 备注 |
|---|---|---|
| RawSample | type, value, start, end, source, hkUUID | 缓存 90 天，之后降采样为日聚合 |
| SleepWindow | start, end, segmentsJSON, source, confidence, version | 版本递增，覆盖保留历史 |
| DailyMetric | date, recovery, sleepScore, sleepNeed, sleepDebt, strain, acwr, stress, confidenceJSON | 一日一行 |
| Workout | start, end, type, source, trimp, hrr60, zonesJSON, hkUUID（写回后） | |
| SetLog | workoutID, exerciseID, reps, weight, restSec, order | 力量组次 |
| Exercise | id, nameZh, nameEn, muscleGroup, type(strength/cardio) | 种子 ~60 个 |
| Routine | name, exerciseIDs, targetSets/Reps/Weight | 模板 |
| Checkin | date, energy(1-5), soreness(1-5) | 每日打卡 |
| Baseline | metric, median, mad, computedAt | 28 天滚动，每日更新 |

## 5. 采集策略
| 场景 | 机制 | 频率 |
|---|---|---|
| 夜间/日间被动数据 | enableBackgroundDelivery(.hourly) + HKObserverQuery + 锚定增量查询 | 系统交付（约 5-60min） |
| 睡眠延伸判定 | 窗口结束后 3h 内，后台唤醒时执行 L2 判定 | 每次唤醒一次 |
| 训练（自动/手动） | HKWorkoutSession（.traditionalStrengthTraining 等） | 连续 HR |
| 打卡 | 本地通知 + 手表快捷 UI | 每日一次 |
| 充电 | 检测 charging 状态，暂停一切判定 | — |

## 6. 睡眠窗口系统（L1–L5）
- **L1 段清洗**：合并 gap≤20min 的 asleep 段；丢弃 <5min 的 awake（除非 HR 上升 >15bpm）；剔除 inBed 但活动能量异常段。
- **L2 后台延伸**：窗口结束后 3h 内，每次后台唤醒检查 `步数==0 && 站立==0 && 活动能量<1kcal/min && HR≤夜间中位数+8bpm && 未充电` → 延伸窗口至最新样本；连续 3 次不满足则锁定。延伸段 source=.extended。
- **L3 通知确认**：不做（用户决策 D2）。
- **L4 手动覆盖**：手表拖动（粗）+ iPhone 时间轴拖动（5min 精度）；覆盖存 source=.override，不写回 HealthKit。
- **L5 追溯重算**：拉到新样本即重算当日窗口与评分，version+1。
- **Confidence** = 0.4·HR覆盖率 + 0.3·分期连续性 + 0.3·窗内静止比例 → ●(≥0.8) ◐(0.5-0.8) ○(<0.5)，附原因文案。

## 7. 训练自动识别
- **信号（10min 滚动窗）**：HR≥静息+35 且持续 4min 且 σ低（0.35）；活动能量率≥4kcal/min 持续 5min（0.30）；时段先验（0.20）；CMMotionActivity+步频（0.15）。
- **置信度**：≥0.8 静默起会话+事后通知可改/取消；0.5-0.8 询问；<0.5 忽略。
- **类型推断**：步频高+位移→跑步；步频低+HR高+能量高→力量；步频中+无位移→椭圆机（提示可选）。
- **结束**：HR≤静息+15 持续 5min 且能量率<1.5kcal/min → 通知确认，30s 无响应自动结束。
- **写回**：结束时写 HKWorkout（start/end 回填真实起点，metadata source=Pulse:auto）；若检测到同时段原生 workout 则只读引用不重复写。

## 8. 组次系统（力量训练）
- **手表快速记组（≤3 次交互）**：训练中表盘常驻「记一组」→ 默认复用上组（重量/次数）→ 点确认；步进器微调。
- **休息计时**：记组后自动起 90s（可配）倒计时，剩余 15s 轻触提示。
- **参考值**：进入动作时显示上次同动作 重量×次数。
- **渐进建议**：上次平均次数 ≥ 目标次数 → 建议 +2.5kg。
- **iPhone 端**：完整编辑（改组、删组、补录整场训练、管理动作库与模板）。
- **动作库种子**：~60 个（胸/背/腿/肩/臂/核心 + 有氧），中英文、肌群、类型。

## 9. 评分算法
```
Baseline: 28 天滚动中位数 + MAD，每日更新；前 14 天校准期不出总分
Recovery = 100·σ(0.35·zHRV − 0.25·zRHR − 0.10·z呼吸 − 0.10·|腕温偏移|
                 + 0.20·z睡眠效率 + 0.05·z精力打卡)        # D7：打卡小权重
Sleep    = 40·时长分 + 25·效率 + 20·结构偏离 + 15·规律性（入睡中点σ）
SleepNeed= 7.5h + 0.3·睡眠债 + 每100TRIMP +5min
Strain   = 21·(1−e^(−TRIMP/K))；TRIMP=Σ区间min×[1,2,3,4,5]+0.3·NEAT
ACWR     = mean(Strain,7d)/mean(Strain,28d)；甜区 0.8–1.3；>1.5 告警
Stress   = 日间 HRV 相对夜间基线偏离 + HR 偏离，剔除训练时段
Readiness= f(Recovery, SleepDebt, 昨日Strain, ACWR, 酸痛打卡) → 0–10
HRR60    = 训练结束即刻 HR − 60s 后 HR
```
门控：核心输入不足 → 降级输出 + 标注；z 用 MAD 稳健化。

## 10. HealthKit 读写
**读**：heartRate, heartRateVariabilitySDNN, restingHeartRate, respiratoryRate, appleSleepingWristTemperature, oxygenSaturation, sleepAnalysis, stepCount, activeEnergyBurned, appleStandTime, distanceWalkingRunning, workout, exerciseTime。
**写**：仅 workout（M4 起），metadata 标记来源。睡眠永不写回（D5）。

## 11. 通知（默认全可关）
| 通知 | 时机 | 默认 |
|---|---|---|
| 晨报 | 睡眠窗口锁定后 30min | 开 |
| 自动训练已开始/已结束 | 事件时 | 开 |
| 异常（RHR/呼吸/HRV 连续 2 天超阈） | 晨报内合并 | 开 |

## 12. 电量预算
后台聚合可忽略；每日 1 次训练会话 ≈6-8%；睡眠延伸判定可忽略；24h（含一次训练）剩余 ≥20%。

## 13. UI 规范
中文文案；大数字 SF Rounded ≥56pt；次要文字 ≥14pt；主按钮 ≥44pt；每数字带基线对比+质量徽标；深色优先；色盲友好（颜色+图标双编码）。

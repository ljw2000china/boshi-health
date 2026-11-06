# 薄士 (Boshi) · 个人健康监控

> Apple Watch S9 + iPhone 的双端个人健康监测 App。
> **端侧计算 · 无服务器 · 数据全在本机**。对标 Athlytic：恢复 / 睡眠 / 训练负荷 / 压力 / 睡眠债 / ACWR，并加入专属增强。

- 产品定位与功能：`docs/PRODUCT.md`
- 开发历程：`docs/DEV_HISTORY.md`
- 设计契约：`docs/design.md`
- 阶段规格：`docs/phases/M.md`
- 总计划：`PLAN.md`

---

## 它是什么

「薄士」是一款**只为一个人服务**的健康与训练助手。它同时运行在你的 Apple Watch 和 iPhone 上，两者通过 Watch Connectivity 离线同步（无 App Groups / 无推送 / 无服务器）。

- **手表** = 快速一瞥 + 一次点按：今天的恢复/睡眠/训练负荷/压力，练没练、练哪块、有没有过量。
- **手机** = 完整编辑与深读：睡眠时间轴修正、训练组次补录、"薄士-天气"每周身体地图、渐进曲线、趋势分析、睡眠/训练写回 HealthKit。

所有数据由 Apple Watch 的传感器（心率、心率变异性 HRV、静止心率、血氧、睡眠、锻炼、步数）在本地采集并推理，**不上传任何服务器**。

---

## 核心能力

### 恢复体系（对标 Athlytic，无订阅）
| 指标 | 说明 |
|---|---|
| **恢复度 Recovery** | 基于静止心率 / HRV / 静息心率变化 + 主观打卡，0–100 |
| **睡眠分 Sleep Score** | 睡眠时长 + 深度 + 稳定性推断，0–100 |
| **训练负荷 Strain** | 依据锻炼能量 / 心率负荷折算，0–20+ |
| **压力 Stress** | 心率 / HRV 推导，1–5 |
| **睡眠债 Sleep Debt** | 实际 vs 需求，小时计 |
| **准备度 Readiness** | 恢复 × 睡眠耦合，0–100 |
| **ACWR** | 28 天急性/慢性负荷比，越界预警 |

### 专属增强（超出 Athlytic）
- **睡眠窗口自动修正**：手表检测到更晚的入睡/更早的醒来时，自动把当夜睡眠窗对齐到真实时段（事后可手动拖动再修正）。
- **训练自动检测 + 静默开始**：置信度 ≥0.8 自动起会话（无需手动按"开始"），训练自动写回系统健身记录。
- **力量训练组次系统**：
  - 动作库 ~60 个常用动作（胸/背/腿/肩/臂/核心…）
  - 手表快速记组：重量+次数，休息计时，上次同动作参考，简单渐进建议
  - 手机补录 / 编辑（左滑改删）、日期整体平移
  - 每周身体地图 + 每动作渐进曲线
- **「薄士-天气」**: 每天一句画风搞笑的训练/休息天气文案。
- **每日精力/酸痛打卡**（1–5）纳入恢复（小权重）。
- **表情包图标 + 表盘复杂功能**：今日训练 + 一句话笑话 + 一周周点。
- **自定义主题**：渐变背景 / 手机照片墙纸 / 毛玻璃卡片透明度 / 标题字体。

---

## 平台与隐私

- **Apple Watch S9 + watchOS 11**，iPhone iOS 18+，双端 SwiftUI。
- 纯端侧：不接入任何服务器 / 广告 / 第三方 SDK。
- HealthKit 读写：睡眠绘图、训练、心率、HRV、静止心率、血氧、步数、能量。
- 免费个人证书：7 天签名，`scripts/resign.sh` 一键重签重装。
- 无 App Groups / iCloud / 推送（受限于免费证书）。

---

## 构建

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成。改工程结构 → 编辑 `project.yml` → 重新 `xcodegen generate`（勿手改 `Pulse.xcodeproj`）。

```bash
# 生成/重新生成工程
xcodegen generate

# iOS（模拟器）
xcodebuild -scheme PulsePhone -destination 'platform=iOS Simulator,name=iPhone 16' build

# watchOS（generic，仅编译校验）
xcodebuild -scheme PulseWatch -destination 'generic/platform=watchOS' build

# 单元测试（104 例）
xcodebuild -scheme PulsePhone \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## 真机安装（免费证书）

1. Xcode → Settings → Accounts → 添加你自己的 Apple ID（免费）。
2. 在 `project.yml` 的每个 target 里填你自己的 `DEVELOPMENT_TEAM`，重新 `xcodegen generate`。
3. 连接设备：
   - `./scripts/resign.sh phone`（iPhone）
   - `./scripts/resign.sh watch`（Apple Watch，需已配对并解锁）
4. 首次安装：设备 设置 → 通用 → VPN与设备管理 → 信任开发者证书。
5. 7 天到期后打不开：重跑 `./scripts/resign.sh …` 覆盖安装即可（HealthKit 数据在系统健康 App，不丢失）。

> 本仓库不提交任何个人签名 / Team ID / 设备 UDID。请设置成你自己的。

---

## 结构

```
WatchPulse/     watchOS App（单 Target，含 Widget 扩展）
PhonePulse/     iOS 伴侣 App
PulseWidget/    watchOS Widget（表盘复杂功能）
Shared/         双 Target 共用源码
  HK/              HealthKit 授权、同步、写回、诊断
  Pipeline/        数据管线（摄取→睡眠窗→评分→基线）
  Scoring/         恢复/睡眠/负荷/压力/ACWR/准备度算法
  Sleep/           睡眠推断与窗口构建
  Store/           SwiftData 持久化模型
  Sync/            手表↔手机 WatchConnectivity 同步
  UI/              共享 UI（主题/趋势/训练/打卡/通用组件）
  Workout/         训练检测、组次、模板、写回
  Notify/          晨间简报
scripts/        重签重装 / 图标生成
docs/           产品、设计、开发历程、阶段与评审
```

## 许可

MIT — 见 [LICENSE](LICENSE)。
# M2–M5 审查记录

## 审查方式

子代理小范围抽查（≤3 问题/次）+ orchestrator 汇总修复。子代理长输出仍触发 Upstream stream failed，窄范围任务可用。

基线：PulsePhone 模拟器 74/74 通过；手表 swiftc -typecheck 0 错误。

---

## 代码审查发现

### M2 评分引擎 — PASS

- Recovery/Strain/ACWR/Stress/Readiness/SleepDebt 六个公式均按 design.md §9 实现
- 占位分权重重归一化（M1 修复延续）
- 28 天基线门控 + 14 天校准期一致

### M4 训练检测 — PASS_WITH_NITS

**已记 nits：**
1. `hrSignal` 缺 σ 低检查（design.md §7 要求「HR≥静息+35 且持续 4min 且 σ低」）→ 偶发心率尖峰可能误触发。**标为 TODO-M4+**，需原始 HR 序列计算滚动 σ
2. `inferType` 无步频/位移输入（§7 要求「步频高+位移→跑步」）→ 简化版用 HR/能量比近似，标为 TODO-M4+，需 CMMotionActivity/CMPedometer 接入
3. `shouldEnd` 只返回 Bool，§7「通知确认 30s 无响应自动结束」流程需上层状态机补

### M5 组次记录 — PASS

- 60 个种子动作覆盖 7 个肌群，ID 唯一
- SetLogger 记组/查参考值/渐进建议逻辑正确
- SwiftData 查询 `let` → `var` 修复

---

## 产品审查发现

### OverviewView — 已修

1. **Strain 0.0 伪装成有效值**：无数据时显示 0.0 而非 "--" → **已修**（strain 改 Double?）
2. **诊断串直接当用户提示**：标定期同时显示「标定期 D3」和橙色「核心输入缺失」→ **已修**（标定期隐藏诊断 note）

---

## 结论

- code: **PASS_WITH_NITS**（M4 σ/步频 TODO 记入 nits）
- product: **PASS**（2 个 UI 问题已修）

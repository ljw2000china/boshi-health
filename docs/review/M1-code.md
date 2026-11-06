# M1 代码审查记录

## 审查方式说明

派给 `code-reviewer` 子代理的审查提示词多次触发 `Upstream stream failed`（输出超过 4000 字节时出现），
改为由 orchestrator 派多个小范围审查子任务（每次 ≤3 个问题），汇总如下。

基线：PulsePhone 模拟器 build+test 27/27 → 修复后 28/28 全绿；手表 `swiftc -typecheck` 0 错误。

---

## 代码审查者发现（共 6 个致命/阻塞问题）

### C1. rebuildNight ↔ L2 延伸版本乒乓（已修）

- 位置：`DataPipeline.swift:78–83`
- L2 延伸出 extended 版本后，任意新样本摄入触发 L1 重算 → 与 latest(extended) 不等 → 插入 system 新版本（end 回退）→ 再触发 L2 延伸 → 无限交替递增
- **修复**：无变化判定改为与「最近的 system 版本」比对；extended 版本继承其 end，L1 重算不再回滚 L2 延伸

### C2. 删除路径不触发重算（已修）

- 位置：`DataPipeline.swift ingest`
- 删除样本只 `ctx.delete(s)`，未收集被删样本 start 日期 → 对应 dayKey 永远不重算
- **修复**：删除前收集 `s.start` 一并传给 `recomputeAffectedDays`

### C3. L2 时间上限无结构化表达（已修）

- `L2Tracker` 只有 `failCount/locked`，3h 上限完全靠调用方传参判断，结构无法表达「超时即锁定」
- **修复**：新增 `canExtend(now:windowEnd:)` 方法，由 tracker 内部同时判 `locked` + `elapsed > 3h`

### C4. 规律性分数跨午夜误算（已修）

- `regularityScore` 把午夜附近的 23:59/00:01 算成相差约 24h，规律性拿 0 分
- **修复**：改用「相邻 unwrap」处理跨午夜样本，实测 23:59/00:01 差 2 分钟 → 规律性 >0.9
- 补单测：`testRegularityCrossMidnightBoundary`

### C5. 占位分抬高总分（已修）

- `structureDeviation == nil` 时占位 0.5 直接计入，结构 10 分 + 规律性 7.5 分固定抬高
- **修复**：占位分项做权重重归一化（只对真实分项求总分），note 标注「占位（不计入）」

### C6. 结构偏离分命名歧义（已修）

- 参数叫 `structureDeviation`（偏离度），实际按「分数」（1.0=完美）参与公式
- **修复**：参数语义不变（占位 0.5），注释明确「偏离度的反向分」；`testPerfectSleepScores100` 传入 1.0 表示完美

---

## 非阻塞 nits（记入 docs/nits.md）

- `L2Tracker` 3h 上限仍无持久化（重启后 failCount 重置，对延伸 3h 内的窗口可能多判定一次）
- `decodeSegments` 静默失败返回 `[]`
- 全文 12 处 `try?` 吞错误，应至少加 `os_log`
- `dayKey` 手动 String(format:)，0 年月日产非法 key
- `Confidence.reason` 阈值（0.7/0.8/0.8）无 design.md 出处

---

## 结论

PASS_WITH_NITS（全部阻塞项已修，nits 非阻塞）

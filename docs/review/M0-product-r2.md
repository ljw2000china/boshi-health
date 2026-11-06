# M0 复审报告（r2）— 结论：PASS

初评致命项已真实修复，修复包其余项全部落地，量规 16/16 无致命项。

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| 1 | devicectl 位置参数 + --device | ✅ | resign.sh:107 `xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"`；与本机 `devicectl ... --help` 实测用法逐字一致 |
| 2 | APP_PATH 按 scheme | ✅ | resign.sh:46-56 case 分支：phone→`Debug-iphoneos`，watch→`Debug-watchos`，产物缺失有报错兜底（:71-74） |
| 3 | DEVICE_ID 兜底 | ✅ | :79-97 环境变量优先→按目标自动挑选（Watch 型号/非 Watch）→解析失败报错并给设置示例。实机验证：本机仅配对 Watch 时 phone 自动挑选为空、正确进入报错引导；报错示例 ID（<watch-udid>）正是本机 Watch 真实 Identifier，系真实运行痕迹 |
| 4 | 验证痕迹 | ✅ | 脚本头注释（:32-33）记录「实测 Xcode 26」用法；错误信息含实机设备 ID；`bash -n` 通过 |
| 5 | 24h 计数截断 ≥5000 | ✅ | HKService.swift:53,66-75（limit+1 探测截断）；手表 DebugDataView.swift:86「24h ≥N」、手机 :98 同步展示 |
| 6 | 手表次要文字 ≥14pt | ✅ | DebugDataView.swift:13 `secondaryFont = .system(size: 14)` 全量替换原 caption2/footnote；行内最小为 .subheadline（15pt） |
| 7 | 授权被拒就地提示 | ✅ | 双端（Watch:54-62 / Phone:50-57）状态未变即显示「系统不再弹出授权框…」提示，按钮不再静默无效 |
| 8 | README id 兜底说明 | ✅ | README.md:35-36 destination name 匹配失败改用 simctl 列表 id |
| 9 | 双端占位图标 | ✅ | 两端 AppIcon.appiconset 均含 AppIcon.png（9.8/9.9KB）且 Contents.json 已引用 |

**遗留 nit（不阻塞）**：README 真机一节未提 `DEVICE_ID` 环境变量（仅脚本头注释与报错信息覆盖）；M0-product-r2.md 仍为空占位，建议将本报告归档于此。

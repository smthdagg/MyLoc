# MyLoc 测试与验收报告

- **日期**：2026-11-26
- **构建环境**：Xcode 27.2 (iOS 27.2 SDK / Deployment Target iOS 26.0)，Rust 1.97.1 (`idevice v0.1.68`)

## 1. 自动化测试结果
| 套件 | 命令 | 结果 |
|---|---|---|
| Rust 引擎单测 | `cargo test --manifest-path Rust/myloc-engine/Cargo.toml` | **通过**（2/2） |
| Rust iOS 交叉编译 | `./scripts/build-rust-xcframework.sh` | **通过**（产出 `Frameworks/MyLocEngine.xcframework`，含真机 + 模拟器） |
| Swift 核心单测 | `swift test --package-path MyLocCore` | **通过**（8/8，覆盖坐标系、路线、GPX、配对校验、脱敏诊断、存储节流、Mock 引擎） |

## 2. 验收标准（AC-01 ~ AC-20）状态
| 编号 | 验收项 | 当前状态 | 说明 |
|---|---|---|---|
| AC-01 | iOS 26.x 真机安装并启动 | 待真机签装 | 需在 Xcode 选择你的免费 Apple ID 签名安装 |
| AC-02 | 配对导入校验 | 逻辑已通过单测 | `testPairingValidator` 已验证有效/空/损坏 plist |
| AC-03 | 固定位置写入与读回 | 待真机验证 | Rust `LocationSimulationClient::set` 已集成 |
| AC-04 | 会话中改点不重连 | 逻辑已通过单测 | `testMockEngine` 验证 `connectCount == 1` |
| AC-05 | 停止并恢复 | 逻辑已通过单测 | `clearLocation` + `disconnect` 已实现 |
| AC-06 | 后台/锁屏 10 分钟保持 | 待真机验证 | 已实现 `BackgroundKeepAlive` + 4s 心跳 |
| AC-07 | 网络切换恢复 | 待真机验证 | 前台恢复自动探测隧道 |
| AC-08 | 杀进程恢复提示 | 已实现 | 启动弹出四选项提示，不自动执行 |
| AC-09 | 步行路线与配速 | 逻辑已通过单测 | `testRouteEngine` 验证推进与反向 |
| AC-10 | 诊断文本脱敏 | **已通过单测** | `testDiagnosticsSanitization` 确认不含坐标/密钥/PIN/设备名 |
| AC-11 | 无网络上报 | 待抓包确认 | 代码无任何第三方 SDK 或自发 HTTP 请求 |
| AC-12 | 60 分钟稳定性 | 待真机验证 | — |
| AC-13 | 隧道缺失引导 | 已实现 | 3s 超时提示并支持跳转 LocalDevVPN 自动继续 |
| AC-14 | 11 种失败阶段 | 已实现 | `FailureStage` 与 Rust `MyLocStatus` 一一对应 |
| AC-15 | 配对失效引导 | 已实现 | `pairVerifyRejected` 映射至明确重新导入提示 |
| AC-16 | 全球坐标系 | **已通过单测** | `testCoordinateConversion` 验证北京/上海/深圳 < 1m，港澳台/伦敦/纽约直通 |
| AC-17 | 重置 App | **已通过单测** | `LocalDataStore.resetAll()` + Keychain 删除 |
| AC-18 | 无障碍与本地化 | 已实现 | 标准 SwiftUI 动态字体与 `accessibilityLabel` |
| AC-19 | iOS 27 回归 | 待真机验证 | 已使用 iOS 27.2 SDK 编译验证 |
| AC-20 | 许可合规 | **已通过** | `THIRD_PARTY.md` 收录 `idevice` MIT 全文，独立工程无外部复制代码 |

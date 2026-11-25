# M0 预研结论汇总

## S-01: `idevice` iOS 交叉编译
- 目标环境：Xcode 27.2（iOS 27.2 SDK / Simulator 27.2 SDK），Rust 1.97.1。
- 已安装 target：`aarch64-apple-ios`、`aarch64-apple-ios-sim`。
- 选定版本：`idevice = "0.1.68"`（MIT）。
- 导出形式：Rust `staticlib`（`libmyloc_engine.a`）+ C 头文件 `myloc_engine.h` + `module.modulemap`，通过 `xcodebuild -create-xcframework` 打包为 `MyLocEngine.xcframework`（支持真机 `aarch64-apple-ios` 与模拟器 `aarch64-apple-ios-sim`）。
- FFI 边界原则：所有函数 `extern "C"`，使用 `std::panic::catch_unwind` 防止 panic 跨 FFI 边界；所有状态以显式错误码返回；线程安全由 Rust 内部 `Mutex` + `tokio::runtime::Runtime` 保证。

## S-02: 后台保活方案（免费账号约束）
- 因无付费开发者账号，不使用 App Extension（无 NetworkExtension）。
- 采用 **方案 B（UIBackgroundModes）**：在 `Info.plist` 中声明 `location` 与 `audio`（无需付费 entitlement）。
- 实现策略：会话激活期间按用户设置可选启用低功耗保活（`CLLocationManager` 持续监听 + 可选静音音频会话保活），同时在 UI 中如实说明受 iOS 系统调度影响，并提供 4 秒心跳保活与异常退出后的会话恢复机制（FR-701~704）。

## S-03: 坐标系策略（全球地区感知）
- 内部模型统一使用 **WGS-84**。
- 仅当坐标位于中国大陆境内（粗略多边形判定，排除香港、澳门、台湾）时，提供 GCJ-02 ↔ WGS-84 双向转换；港澳台、欧洲、美洲及其他地区直通。
- 往返误差校验：单元测试覆盖北京、上海、深圳、香港、台北、伦敦、纽约，要求往返误差 `< 1 m`（NFR-110）。
- 说明：由于 iOS MapKit 在中国大陆显示底图时使用 GCJ-02 偏移，而 DVT `LocationSimulation` 写入的是设备底层 WGS-84 坐标，实际真机可在设置中开启/关闭“大陆坐标自动校正”以便按实测微调。

## S-04: 配对文件格式与校验
- 支持 `.plist` 与 `.mobiledevicepairing`（XML 或二进制 plist）。
- 校验规则：可被 `PropertyListSerialization` 解析为字典，且包含关键字段（如 `HostID`/`SystemBUID` 或 `UDID`/`DeviceCertificate`/`HostCertificate`/`RootCertificate` 或 `remote_pairing` 结构），拒绝空文件、损坏文件和非字典 plist。
- 存储：仅存入 Keychain，访问级别 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不进入 iCloud/iTunes 备份，不写入日志。

## S-05: 免费账号分发与限制
- 单体 App，无 Extension，节省免费账号的 3 个活跃 App 名额与每周 10 个 App ID 限额。
- 7 天重签限制在引导页和设置页中明确说明。

## S-06: iOS 26 / iOS 27 兼容策略
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`，编译 SDK 为 iOS 27.2。
- 所有 iOS 27 特有 API（如有）均使用 `if #available(iOS 27.0, *)` 保护。
- iOS 27 设备端发起配对仅保留接口占位，不在 M1–M3 实现。

## C-01: 许可合规
- `idevice` 为 MIT 许可，已完整收录至 `THIRD_PARTY.md`。
- 不引入任何 LocalDevVPN/StosVPN 代码，仅通过本地 TCP 探测与 URL Scheme 引导。

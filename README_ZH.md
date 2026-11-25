# MyLoc（中文说明）

**MyLoc** 是一款完全独立实现的开源 iOS 26.0+（兼容 iOS 27）本地位置模拟与开发测试工具。界面基于 SwiftUI + MapKit，底层引擎使用 Rust 与 MIT 许可的 [`idevice`](https://github.com/jkcoxson/idevice) 构建，通过 **RPPairing + TLS-PSK CDTunnel → RSD → DVT LocationSimulation** 实现免电脑的本地位置模拟。

[English Documentation](README.md)

---

## 核心特性

- **固定位置模拟**：地图点选、全球搜索、经纬度直接输入；会话中改点秒级生效且不重连，支持 4 秒心跳保活。
- **全球自由搜索与坐标系处理**：支持全球地点搜索（`MKLocalSearch` + `CLGeocoder` + 内置全球快捷城市）；内部统一 WGS-84，仅对中国大陆区域自动处理 GCJ-02 偏移，港澳台及欧美地区直通。
- **路线与移动模拟**：支持步行/骑行/驾车路线（含直线插值兜底）、配速调节、暂停/继续/反向、虚拟摇杆微调及 GPX 1.1 导入导出。
- **收藏、历史与异常恢复**：收藏管理、最近 30 条历史记录；异常退出重启后提供明确恢复选项（绝不自动执行）。
- **隐私与零上报**：无任何统计、无遥测、无服务器；配对记录仅加密存于本机 Keychain（`WhenUnlockedThisDeviceOnly`）。
- **免费 Apple ID 友好**：单体 App 无 Extension，可直接用 SideStore / AltStore / Sideloadly 侧载，搭配 App Store 免费的 **LocalDevVPN** 使用。

---

## 使用前准备

1. **iPhone**：运行 **iOS 26.0+**，并在 **设置 → 隐私与安全性 → 开发者模式** 中开启开发者模式。
2. **LocalDevVPN**：在 App Store 免费下载安装，用于提供本机 `10.7.0.1:49152` 虚拟隧道。
3. **电脑（仅首次需要）**：macOS / Windows / Linux 均可，用于通过 USB 生成当前手机专属的 `.mobiledevicepairing` 配对文件。

---

## 安装与配对教程

### 第一步：安装 `MyLoc.ipa`
- 从 GitHub [Releases](../../releases) 下载 `MyLoc.ipa`（或按下方说明从源码编译）。
- 使用 **SideStore**、**AltStore**、**Sideloadly** 或 **Xcode**，用你自己的免费 Apple ID 将 `MyLoc.ipa` 侧载安装到 iPhone。
- 在手机 **设置 → 通用 → VPN 与设备管理** 中信任开发者证书。
  > 提示：免费 Apple ID 签名有效期为 7 天，推荐使用 SideStore 在手机端自动续签。

### 第二步：生成本机配对文件（一机一次，长期复用）
由于 iOS 26 安全限制，首次配对必须通过 USB 线连接电脑生成：

**方式 A：使用图形化工具 `idevice_pair`（推荐，支持 Windows / macOS / Linux）**
1. 用 USB 数据线将 iPhone 连接电脑，解锁手机并在弹窗中点击 **“信任”**。
2. 运行开源工具 [`idevice_pair`](https://github.com/jkcoxson/idevice_pair)，选择你的设备并导出 `.mobiledevicepairing` 文件。

**方式 B：使用本项目自带命令行工具（macOS / Linux）**
```bash
cargo run --manifest-path Rust/myloc-engine/Cargo.toml --bin export_pairing -- <你的设备UDID> my_iphone.mobiledevicepairing
```

### 第三步：导入配对文件并开始模拟
1. 将 `.mobiledevicepairing` 文件传到 iPhone 的 **“文件”** App（可通过 AirDrop、微信文件传输助手或 iCloud）。
2. 打开 **MyLoc**，点击顶部状态栏（或 **设置 → 配对管理**），点击 **“选择 .mobiledevicepairing 文件导入”**。
3. 打开 **LocalDevVPN** 并开启本地隧道开关。
4. 回到 **MyLoc**，在地图上点选目标位置（或点击上方全球快捷城市 / 搜索地点），点击 **“开始位置模拟”**。
5. 使用完毕后，点击 **“停止并恢复”** 即可让系统恢复真实 GPS 定位。

---

## 从源码编译

环境要求：macOS + Xcode 26/27+、Rust（已安装 `aarch64-apple-ios` 与 `aarch64-apple-ios-sim`）。

```bash
# 1. 运行 Rust 单测并构建 MyLocEngine.xcframework
cargo test --manifest-path Rust/myloc-engine/Cargo.toml
./scripts/build-rust-xcframework.sh

# 2. 运行 Swift 核心单测
swift test --package-path MyLocCore

# 3. 生成 Xcode 工程
python3 scripts/generate-xcodeproj.py

# 4. 在 Xcode 中打开工程，选择你的 Apple ID Team 后真机运行
open MyLoc.xcodeproj
```

---

## 开源许可与致谢

本项目采用 [MIT License](LICENSE) 开源。第三方开源许可声明见 [THIRD_PARTY.md](THIRD_PARTY.md)（基于 `idevice`）。

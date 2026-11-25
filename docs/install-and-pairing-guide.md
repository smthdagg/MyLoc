# MyLoc 安装与配对说明

## 一、人工操作版

### 前提条件
- iPhone 运行 **iOS 26.0+**（兼容 iOS 27），已开启 **设置 → 隐私与安全性 → 开发者模式**。
- 已安装外部 **LocalDevVPN**（用于建立 `10.7.0.1:49152` 本地虚拟隧道）。
- 已有本机的 `.plist` 或 `.mobiledevicepairing` 配对文件。

### 编译与安装（Xcode）
1. 构建 Rust 引擎（首次或修改 Rust 代码后）：
   ```bash
   ./scripts/build-rust-xcframework.sh
   ```
2. 打开 `MyLoc.xcodeproj`，在 Signing & Capabilities 中选择你的个人免费 Apple ID Team，修改 Bundle Identifier（例如 `com.<你的标识>.myloc`）。
3. 连接真机，点击 Run 编译安装。
4. 在设备上信任开发者证书（设置 → 通用 → VPN 与设备管理）。
5. 免费 Apple ID 签名有效期为 **7 天**，到期前通过 Xcode 或 SideStore/AltStore 重新签名即可。

### 首次使用
1. 打开 MyLoc 引导页，点击 **导入设备配对文件**，选择 `.plist` / `.mobiledevicepairing`。
2. 点击 **打开 LocalDevVPN 建立本地隧道**，开启 VPN 后返回 MyLoc。
3. 在地图上点选或搜索目标位置，点击 **开始位置模拟**。
4. 结束时点击 **停止并恢复**，等待系统重新获取真实定位。

---

## 二、AI / CI 自动化构建版

```bash
# 1. 运行 Rust 单元测试
cargo test --manifest-path Rust/myloc-engine/Cargo.toml

# 2. 交叉编译 iOS + Simulator 静态库并打包 xcframework
./scripts/build-rust-xcframework.sh

# 3. 运行 Swift 核心逻辑单元测试
swift test --package-path MyLocCore

# 4. 重新生成 Xcode 工程（如新增 Swift 文件）
python3 scripts/generate-xcodeproj.py

# 5. 构建 iOS 真机（无签名验证）或模拟器产物
xcodebuild -project MyLoc.xcodeproj -scheme MyLoc -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

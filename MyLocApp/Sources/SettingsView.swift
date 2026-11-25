import SwiftUI
import UniformTypeIdentifiers
import UIKit
import MyLocCore

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPairingImporter = false
    @State private var showAutoPairing = false
    @State private var showDeletePairingConfirm = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("配对管理") {
                    if let summary = viewModel.pairingSummary {
                        LabeledContent("设备", value: summary.deviceName)
                        LabeledContent("型号", value: summary.model)
                        LabeledContent("指纹", value: summary.fingerprint)
                        Button("App 内自动配对（6 位码）") { showAutoPairing = true }
                        Button("重新导入配对文件") { showPairingImporter = true }
                        Button("删除配对记录", role: .destructive) { showDeletePairingConfirm = true }
                    } else {
                        Text("尚未导入配对记录").foregroundStyle(.secondary)
                        Button("App 内自动配对（6 位码）") { showAutoPairing = true }
                        Button("从文件导入配对记录") { showPairingImporter = true }
                    }
                }

                Section("显示与单位") {
                    Picker("外观", selection: $viewModel.preferences.appearance) {
                        Text("跟随系统").tag(AppAppearance.system)
                        Text("浅色").tag(AppAppearance.light)
                        Text("深色").tag(AppAppearance.dark)
                    }
                    Picker("地图样式", selection: $viewModel.preferences.mapStyle) {
                        Text("标准").tag(MapStyleOption.standard)
                        Text("卫星").tag(MapStyleOption.satellite)
                        Text("混合").tag(MapStyleOption.hybrid)
                    }
                    Picker("距离单位", selection: $viewModel.preferences.units) {
                        Text("跟随系统").tag(DistanceUnit.system)
                        Text("公制 (km)").tag(DistanceUnit.metric)
                        Text("英制 (mi)").tag(DistanceUnit.imperial)
                    }
                    Toggle("中国大陆坐标自动校正 (GCJ-02)", isOn: $viewModel.preferences.autoAdjustMainlandChinaGCJ02)
                    Toggle("会话期间启用后台保活", isOn: $viewModel.preferences.backgroundKeepAliveEnabled)
                }

                Section("连接健康与诊断") {
                    LabeledContent("配对状态", value: viewModel.hasPairing ? "已配置" : "未配置")
                    LabeledContent("隧道状态", value: viewModel.tunnelReachable ? "已连通" : "未连通")
                    LabeledContent("会话状态", value: viewModel.sessionState.displayTextZh)
                    LabeledContent("最近错误", value: viewModel.lastFailure?.diagnosticCode ?? "无")
                    Button("检测隧道连通性") {
                        Task { _ = await viewModel.checkTunnel() }
                    }
                    Button("复制脱敏诊断文本") {
                        UIPasteboard.general.string = viewModel.buildDiagnosticsText()
                        viewModel.statusBannerMessage = "诊断文本已复制（不含坐标与密钥）。"
                    }
                }

                Section("免费账号提示") {
                    Text("免费 Apple ID 侧载签名有效期为 7 天，到期前需重新签名。隧道依赖外部 LocalDevVPN。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("重置应用", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
            .navigationTitle("设置")
            .onChange(of: viewModel.preferences) { _, _ in
                viewModel.savePreferences()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPairingImporter, allowedContentTypes: [.propertyList, .data]) { result in
                if case .success(let url) = result {
                    viewModel.importPairingFile(url: url)
                }
            }
            .sheet(isPresented: $showAutoPairing) {
                AutoPairingView(viewModel: viewModel)
            }
            .confirmationDialog("确定删除本机配对记录？", isPresented: $showDeletePairingConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) { viewModel.deletePairing() }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("重置将清除配对、收藏、历史与全部偏好设置，确定继续？", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("全部重置", role: .destructive) {
                    Task {
                        await viewModel.resetApp()
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

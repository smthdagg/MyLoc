import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showPairingImporter = false
    @State private var showAutoPairing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("欢迎使用 MyLoc")
                        .font(.largeTitle.bold())

                    Text("MyLoc 是一款独立实现的本地位置模拟与开发测试工具，适用于 iOS 26.0+ 自有设备。")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("仅用于本人设备开发与测试，模拟定位会影响全部位置类 App。", systemImage: "exclamationmark.triangle")
                        Label("配对记录仅存于本机 Keychain，无任何服务器与数据上报。", systemImage: "lock.shield")
                        Label("免费账号侧载需每 7 天重签，隧道依赖外部 LocalDevVPN。", systemImage: "network")
                    }
                    .font(.subheadline)

                    Divider()

                    VStack(spacing: 12) {
                        Button {
                            showAutoPairing = true
                        } label: {
                            Label("App 内自动配对（6 位配对码）", systemImage: "iphone.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showPairingImporter = true
                        } label: {
                            Label(viewModel.hasPairing ? "配对记录已就绪（可重新导入）" : "从文件导入配对记录", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.openLocalDevVPN()
                        } label: {
                            Label("打开 LocalDevVPN 建立本地隧道", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.completeOnboarding()
                        } label: {
                            Text("进入 MyLoc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .fileImporter(isPresented: $showPairingImporter, allowedContentTypes: [.propertyList, .data]) { result in
                if case .success(let url) = result {
                    viewModel.importPairingFile(url: url)
                }
            }
            .sheet(isPresented: $showAutoPairing) {
                AutoPairingView(viewModel: viewModel)
            }
        }
    }
}

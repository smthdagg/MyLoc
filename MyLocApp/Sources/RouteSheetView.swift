import SwiftUI
import UniformTypeIdentifiers
import MyLocCore

struct RouteSheetView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: SessionKind = .walk
    @State private var showGPXImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("路线模式") {
                    Picker("模式", selection: $selectedKind) {
                        Text("步行").tag(SessionKind.walk)
                        Text("骑行").tag(SessionKind.ride)
                        Text("驾车").tag(SessionKind.drive)
                    }
                    .pickerStyle(.segmented)

                    if selectedKind == .walk {
                        Picker("步行配速", selection: $viewModel.selectedWalkPace) {
                            ForEach(WalkPace.allCases, id: \.self) { pace in
                                Text(pace.displayNameZh).tag(pace)
                            }
                        }
                    }
                }

                Section("路线控制") {
                    if let dest = viewModel.selectedPlace {
                        Text("终点：\(dest.name)")
                        Button("开始沿路线模拟") {
                            Task {
                                await viewModel.startRoute(to: dest, kind: selectedKind, pace: viewModel.selectedWalkPace)
                                dismiss()
                            }
                        }
                    } else {
                        Text("请先在地图上选择一个终点。").foregroundStyle(.secondary)
                    }

                    if let progress = viewModel.routeProgress {
                        let unit = viewModel.preferences.units
                        HStack {
                            Text("已行进")
                            Spacer()
                            Text("\(unit.formatDistance(meters: progress.traveledMeters)) / \(unit.formatDistance(meters: progress.totalMeters))")
                        }
                        HStack {
                            Button(viewModel.isRoutePaused ? "继续" : "暂停") {
                                viewModel.toggleRoutePause()
                            }
                            Spacer()
                            Button("反向") {
                                viewModel.reverseRoute()
                            }
                        }
                    }
                }

                Section("GPX 1.1") {
                    Button("导入 GPX 路线") {
                        showGPXImporter = true
                    }
                }

                Section("摇杆微调（不记录历史）") {
                    VStack(spacing: 8) {
                        Button("↑ 北") { Task { await viewModel.nudgeJoystick(dLat: 0.0002, dLon: 0) } }
                        HStack(spacing: 24) {
                            Button("← 西") { Task { await viewModel.nudgeJoystick(dLat: 0, dLon: -0.0002) } }
                            Button("→ 东") { Task { await viewModel.nudgeJoystick(dLat: 0, dLon: 0.0002) } }
                        }
                        Button("↓ 南") { Task { await viewModel.nudgeJoystick(dLat: -0.0002, dLon: 0) } }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("路线与移动")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data]) { result in
                if case .success(let url) = result {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        Task { await viewModel.startGPXRoute(data: data) }
                    }
                }
            }
        }
    }
}

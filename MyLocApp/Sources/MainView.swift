import MapKit
import SwiftUI
import MyLocCore

struct MainView: View {
    @Bindable var viewModel: AppViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var coordinateInputText = ""
    @State private var showCoordinateAlert = false
    @State private var showStopConfirm = false
    @State private var showRouteSheet = false
    @State private var showPlacesSheet = false
    @State private var showSettingsSheet = false
    @State private var showAutoPairingSheet = false

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    if let selected = viewModel.selectedPlace {
                        Marker(selected.name, coordinate: CLLocationCoordinate2D(latitude: selected.latitude, longitude: selected.longitude))
                            .tint(.orange)
                    }

                    if let sim = viewModel.simulatedCoordinate {
                        Annotation("模拟位置", coordinate: CLLocationCoordinate2D(latitude: sim.latitude, longitude: sim.longitude)) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(radius: 3)
                        }
                    }

                    if viewModel.routeWaypoints.count >= 2 {
                        MapPolyline(coordinates: viewModel.routeWaypoints.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(.blue, lineWidth: 4)
                    }
                }
                .mapStyle(resolvedMapStyle)
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                }
                .onTapGesture { screenPoint in
                    if let coord = proxy.convert(screenPoint, from: .local) {
                        viewModel.selectCoordinate(Coordinate(latitude: coord.latitude, longitude: coord.longitude))
                    }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in
                    viewModel.followSimulatedLocation = false
                })
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                topBar
                if !viewModel.searchSuggestions.isEmpty {
                    searchSuggestionList
                }
                if let banner = viewModel.statusBannerMessage {
                    Text(banner)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { viewModel.statusBannerMessage = nil }
                }
                Spacer()
                HStack {
                    Spacer()
                    floatingMapControls
                }
                bottomControlCard
            }
            .padding()
        }
        .onChange(of: viewModel.selectedPlace) { _, newPlace in
            if let p = newPlace {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
        .onChange(of: viewModel.simulatedCoordinate) { _, newCoord in
            if viewModel.followSimulatedLocation, let c = newCoord {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
        .alert("输入经纬度", isPresented: $showCoordinateAlert) {
            TextField("例如：39.9042, 116.4074", text: $coordinateInputText)
            Button("确定") {
                if viewModel.selectCoordinateFromText(coordinateInputText) {
                    coordinateInputText = ""
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确定停止位置模拟并恢复真实定位？", isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("停止并恢复", role: .destructive) {
                Task { await viewModel.stopAndRestore() }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("上次会话可能仍在生效", isPresented: $viewModel.showRecoveryAlert) {
            Button("恢复上次位置") { Task { await viewModel.recoverLastSession() } }
            Button("仅恢复真实定位", role: .destructive) { Task { await viewModel.recoverRestoreRealLocation() } }
            Button("忽略", role: .cancel) { viewModel.ignoreRecovery() }
        } message: {
            Text("检测到应用上次异常退出，请选择要执行的操作（不会自动执行）。")
        }
        .sheet(isPresented: $viewModel.showDisclaimerSheet) {
            disclaimerSheet
        }
        .sheet(isPresented: $showRouteSheet) {
            RouteSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $showPlacesSheet) {
            PlacesSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAutoPairingSheet) {
            AutoPairingView(viewModel: viewModel)
        }
    }

    private var mapStyleShortName: String {
        switch viewModel.preferences.mapStyle {
        case .standard:  return "标准"
        case .satellite: return "卫星"
        case .hybrid:    return "混合"
        }
    }

    private var floatingMapControls: some View {
        VStack(spacing: 10) {
            // One-tap Map Style switcher
            Button {
                viewModel.cycleMapStyle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "map")
                    Text(mapStyleShortName).font(.caption2)
                }
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("切换地图样式")

            // One-tap My Location (real or simulated)
            Button {
                if let loc = viewModel.simulatedCoordinate ?? viewModel.realCoordinate {
                    viewModel.followSimulatedLocation = true
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                } else {
                    cameraPosition = .userLocation(fallback: .automatic)
                }
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("我的定位")
        }
    }

    private var resolvedMapStyle: MapStyle {
        switch viewModel.preferences.mapStyle {
        case .standard:  return .standard
        case .satellite: return .imagery
        case .hybrid:    return .hybrid
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索全球地点或输入经纬度", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await viewModel.performSearchSubmit() }
                        }
                    if !viewModel.searchQuery.isEmpty {
                        Button { viewModel.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Button { showCoordinateAlert = true } label: {
                    Image(systemName: "number.square")
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("经纬度输入")

                Button { showSettingsSheet = true } label: {
                    Image(systemName: "gearshape")
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("设置")
            }

            HStack {
                Button {
                    showAutoPairingSheet = true
                } label: {
                    Label(
                        viewModel.hasPairing ? viewModel.sessionState.displayTextZh : "点击进行自动配对",
                        systemImage: viewModel.hasPairing ? (viewModel.sessionState == .active ? "location.fill" : "checkmark.circle") : "iphone.radiowaves.left.and.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.hasPairing ? (viewModel.sessionState == .active ? .blue : .primary) : .orange)
                }
                Spacer()
                Button {
                    if viewModel.tunnelReachable {
                        Task { _ = await viewModel.checkTunnel() }
                    } else {
                        viewModel.openLocalDevVPN()
                    }
                } label: {
                    Label(viewModel.tunnelReachable ? "隧道已连通" : "点击连接隧道", systemImage: viewModel.tunnelReachable ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(viewModel.tunnelReachable ? .green : .orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            // Quick global city chips for 1-tap worldwide jump
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AppViewModel.globalPresets) { preset in
                        Button {
                            viewModel.selectCoordinate(preset.coordinate, name: preset.name, subtitle: preset.subtitle)
                        } label: {
                            Text(preset.name.components(separatedBy: " ").first ?? preset.name)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var searchSuggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.searchSuggestions, id: \.self) { item in
                    Button {
                        Task { await viewModel.selectSearchCompletion(item) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).foregroundStyle(.primary)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bottomControlCard: some View {
        VStack(spacing: 12) {
            if let place = viewModel.selectedPlace {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.headline).lineLimit(1)
                        Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.addFavorite(place)
                        viewModel.statusBannerMessage = "已加入收藏。"
                    } label: {
                        Image(systemName: "star")
                    }
                    .accessibilityLabel("收藏当前地点")
                }
            } else {
                Text("轻点地图或搜索以选择目标位置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if viewModel.sessionState == .failed(.tunnelUnreachable) {
                Button("打开 LocalDevVPN 建立隧道") {
                    viewModel.openLocalDevVPN()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            HStack(spacing: 10) {
                if viewModel.sessionState == .active {
                    Button(role: .destructive) {
                        showStopConfirm = true
                    } label: {
                        Label("停止并恢复", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        viewModel.requestStartFixedSession()
                    } label: {
                        Label("开始位置模拟", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedPlace == nil || viewModel.sessionState.isBusy)
                }

                Button { showRouteSheet = true } label: {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("路线模拟")

                Button { showPlacesSheet = true } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("收藏与历史")

                if !viewModel.followSimulatedLocation && viewModel.simulatedCoordinate != nil {
                    Button { viewModel.followSimulatedLocation = true } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("恢复跟随")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var disclaimerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("合法使用声明").font(.title2.bold())
                Text("MyLoc 仅用于在您本人拥有且已开启开发者模式的设备上进行位置模拟与开发测试。")
                Text("• 模拟位置会影响设备上所有使用定位服务的 App。\n• 请勿用于违反法律法规或第三方服务条款的用途。\n• 本应用不收集、不上传任何位置或配对数据。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("我已阅读并同意") {
                    viewModel.acceptDisclaimerAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showDisclaimerSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

import SwiftUI
import MyLocCore

struct PlacesSheetView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var renamingPlace: Place?
    @State private var newNameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("收藏") {
                    if viewModel.favorites.isEmpty {
                        Text("暂无收藏地点").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.favorites) { place in
                            Button {
                                viewModel.selectCoordinate(place.coordinate, name: place.name, subtitle: place.subtitle)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(place.name)
                                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("重命名") {
                                    renamingPlace = place
                                    newNameText = place.name
                                }.tint(.blue)
                            }
                        }
                        .onDelete(perform: viewModel.deleteFavorites)
                        .onMove(perform: viewModel.moveFavorites)
                    }
                }

                Section {
                    if viewModel.history.isEmpty {
                        Text("暂无历史记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.history) { place in
                            Button {
                                viewModel.selectCoordinate(place.coordinate, name: place.name, subtitle: place.subtitle)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(place.name)
                                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("最近历史（最多 30 条）")
                        Spacer()
                        if !viewModel.history.isEmpty {
                            Button("清空") { viewModel.clearHistory() }
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("收藏与历史")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .alert("重命名收藏", isPresented: Binding(get: { renamingPlace != nil }, set: { if !$0 { renamingPlace = nil } })) {
                TextField("名称", text: $newNameText)
                Button("保存") {
                    if let p = renamingPlace, !newNameText.isEmpty {
                        viewModel.renameFavorite(id: p.id, newName: newNameText)
                    }
                    renamingPlace = nil
                }
                Button("取消", role: .cancel) { renamingPlace = nil }
            }
        }
    }
}

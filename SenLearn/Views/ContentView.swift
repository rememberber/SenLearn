import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var speech: SpeechPlayer
    @AppStorage("lastOpenedBookID") private var lastBook = ""
    @State private var activeBookID: UUID?
    @State private var didRestore = false
    @State private var sheet: Sheet?
    @State private var pickingFile = false
    @State private var pickingPhotos = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var appendDestination: UUID?
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @State private var cancellingImport = false
    @State private var issue: String?
    private let importer = MaterialImporter()
    enum Sheet: String, Identifiable { case settings, sources, camera; var id: String { rawValue } }

    var body: some View {
        ZStack {
            appearance.theme.background.ignoresSafeArea()
            if let id = activeBookID, library.book(id: id) != nil {
                ReaderView(library: library, appearance: appearance, speech: speech, bookID: id,
                           onBack: { speech.stop(); activeBookID = nil; lastBook = "" },
                           onSettings: { sheet = .settings },
                           onAppend: { appendDestination = id; sheet = .sources }).id(id)
            } else {
                LibraryView(library: library, appearance: appearance,
                            onOpen: openBook,
                            onAdd: { appendDestination = nil; sheet = .sources },
                            onSample: importSample,
                            onSettings: { sheet = .settings })
            }
            if importing {
                Color.black.opacity(0.2).ignoresSafeArea()
                VStack(spacing: 18) {
                    ProgressView().controlSize(.large).tint(appearance.theme.accent)
                    Text(cancellingImport ? "正在取消…" : "正在准备书页…").font(.headline)
                    Text("材料会保存在这台设备上").font(.subheadline).foregroundStyle(.secondary)
                    Button("取消") { cancellingImport = true; importTask?.cancel() }
                        .disabled(cancellingImport).buttonStyle(SoftButtonStyle(theme: appearance.theme))
                }.padding(32).background(appearance.theme.surface, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .tint(appearance.theme.accent)
        .onAppear {
            guard !didRestore else { return }; didRestore = true
            if let id = UUID(uuidString: lastBook), library.book(id: id) != nil { activeBookID = id }
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .settings: SettingsView(appearance: appearance, speech: speech)
            case .sources: sourceSheet
            case .camera:
                DocumentCamera(onComplete: { data in
                    sheet = nil
                    startImport { try await importer.importPhotos(data, title: "我的拍照书") }
                }, onCancel: { sheet = nil }, onFailure: { error in sheet = nil; issue = error.localizedDescription })
                .ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.pdf, .image]) { result in
            switch result {
            case .success(let url): startImport { try await importer.importFile(at: url) }
            case .failure(let error): issue = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $selectedPhotos, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: selectedPhotos) { _, photos in
            guard !photos.isEmpty else { return }
            startImport {
                var data: [Data] = []
                var totalBytes = 0
                for photo in photos {
                    try Task.checkCancellation()
                    guard let bytes = try await photo.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    guard bytes.count <= MaterialImporter.maximumFileBytes - totalBytes else {
                        throw MaterialImporter.ImportError.fileTooLarge
                    }
                    totalBytes += bytes.count
                    data.append(bytes)
                }
                return try await importer.importPhotos(data, title: "我的照片书")
            }
            selectedPhotos = []
        }
        .alert("暂时无法完成", isPresented: Binding(get: { issue != nil || library.errorMessage != nil }, set: {
            if !$0 { issue = nil; library.errorMessage = nil }
        })) {
            Button("知道了", role: .cancel) { issue = nil; library.errorMessage = nil }
        } message: { Text(issue ?? library.errorMessage ?? "请稍后重试") }
    }

    private var sourceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(appendDestination == nil ? "把喜欢的书，变成可以点读的书。" : "新书页会接在这本书的最后。")
                    .font(.title2.bold()).padding(.bottom, 6)
                sourceButton("连续拍摄书页", detail: DocumentCamera.isSupported ? "自动裁切 · 一次拍摄多页" : "请在支持扫描的真机上使用", icon: "camera.viewfinder") {
                    sheet = .camera
                }.disabled(!DocumentCamera.isSupported)
                sourceButton("从照片选择", detail: "按选择顺序成书 · 最多 30 张", icon: "photo.on.rectangle.angled") {
                    sheet = nil; pickingPhotos = true
                }
                sourceButton("导入 PDF 或图片", detail: "从「文件」选择本地学习材料", icon: "doc.badge.plus") {
                    sheet = nil; pickingFile = true
                }
                Label("材料保存在本机，无需注册账号", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                Spacer(minLength: 0)
            }.padding(28).background(appearance.theme.background)
                .navigationTitle(appendDestination == nil ? "添加材料" : "继续添加书页")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { sheet = nil } } }
        }.presentationDetents([.medium, .large])
    }

    private func sourceButton(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").font(.footnote.bold())
            }.padding(18).foregroundStyle(appearance.theme.ink).background(appearance.theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func openBook(_ id: UUID) {
        speech.stop(); activeBookID = id; lastBook = id.uuidString
        if let book = library.book(id: id) {
            do { try library.setReadingPosition(bookID: id, index: book.currentPageIndex) }
            catch { issue = error.localizedDescription }
        }
    }

    private func importSample() {
        appendDestination = nil
        startImport {
            let url = try SampleMaterial.makePDF()
            defer { try? FileManager.default.removeItem(at: url) }
            var result = try await importer.importFile(at: url)
            result.title = "Forest Friends · 示例"
            return result
        }
    }

    private func startImport(_ operation: @escaping () async throws -> ImportedMaterial) {
        guard !importing, library.isAvailable else { return }
        speech.stop(); importing = true; cancellingImport = false
        let destination = appendDestination
        importTask = Task { @MainActor in
            defer { importing = false; cancellingImport = false; importTask = nil }
            do {
                let material = try await operation()
                try Task.checkCancellation()
                let id = try library.importMaterial(material, appendingTo: destination)
                openBook(id)
            } catch is CancellationError {
                // No library mutation happens before the cancellation checkpoint.
            } catch { issue = error.localizedDescription }
        }
    }
}

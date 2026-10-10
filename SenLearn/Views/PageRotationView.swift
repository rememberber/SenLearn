import SwiftUI

struct PageRotationView: View {
    let imageURL: URL
    let theme: AppTheme
    let onSave: (ImportedPage) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var turns = 0
    @State private var saving = false
    @State private var issue: String?
    @State private var image: UIImage?
    private let rotator = PageRotator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("把文字转到正方向。保存后会重新识别本页，并替换本页的校对文字。")
                    .font(.subheadline).foregroundStyle(theme.ink.opacity(0.7))
                GeometryReader { geometry in
                    if let image {
                        let odd = !turns.isMultiple(of: 2)
                        let width = odd ? geometry.size.height : geometry.size.width
                        let height = odd ? geometry.size.width : geometry.size.height
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: width, height: height)
                            .rotationEffect(.degrees(Double(turns) * 90))
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            .accessibilityLabel("书页预览，顺时针旋转 \(turns * 90) 度")
                    } else {
                        ContentUnavailableView("无法读取书页", systemImage: "doc.questionmark")
                    }
                }
                HStack(spacing: 20) {
                    Button { turns = (turns + 3) % 4 } label: { Label("向左转", systemImage: "rotate.left") }
                        .accessibilityIdentifier("rotation.left")
                    Button { turns = (turns + 1) % 4 } label: { Label("向右转", systemImage: "rotate.right") }
                        .accessibilityIdentifier("rotation.right")
                }.buttonStyle(SoftButtonStyle(theme: theme)).disabled(saving || image == nil)
                if saving { ProgressView("正在保存书页…") }
            }.padding(24).background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("旋转书页").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }.disabled(saving).accessibilityIdentifier("rotation.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }.disabled(saving || turns == 0 || image == nil)
                            .accessibilityIdentifier("rotation.save")
                    }
                }
        }.tint(theme.accent).interactiveDismissDisabled(saving)
            .onAppear { image = UIImage(contentsOfFile: imageURL.path) }
            .alert("无法保存书页", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
                Button("知道了", role: .cancel) { issue = nil }
            } message: { Text(issue ?? "请重试") }
    }

    private func save() {
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                let result = try await rotator.rotate(imageURL: imageURL, quarterTurns: turns)
                try onSave(result)
                dismiss()
            } catch { issue = error.localizedDescription }
        }
    }
}

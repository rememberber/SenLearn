import SwiftUI

struct CorrectionView: View {
    let page: BookPage
    let imageURL: URL
    let theme: AppTheme
    let onSave: (BookPage) -> Bool
    @State private var lines: [RecognizedLine]
    @Environment(\.dismiss) private var dismiss

    init(page: BookPage, imageURL: URL, theme: AppTheme, onSave: @escaping (BookPage) -> Bool) {
        self.page = page; self.imageURL = imageURL; self.theme = theme; self.onSave = onSave
        _lines = State(initialValue: page.lines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { PageThumbnail(url: imageURL).frame(maxWidth: .infinity).frame(height: 230).listRowBackground(Color.white) }
                Section {
                    Text("只修改识别文字，不改变原始书页。修改后的行可用「听整页」或「文字列表」朗读；逐词位置需要重新确认，因此暂不提供该行的点词操作。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach($lines) { $line in
                    Section {
                        TextField("识别文字", text: $line.text, axis: .vertical).lineLimit(2...6)
                            .accessibilityIdentifier("correction.line.\(line.id)")
                        if let original = line.originalText {
                            Button("恢复原始识别") {
                                line.text = original; line.words = line.originalWords ?? []
                                line.originalText = nil; line.originalWords = nil
                            }
                        } else if let original = page.lines.first(where: { $0.id == line.id }), original.text != line.text {
                            Button("撤销本次修改") { line = original }
                        }
                    }
                }
            }
            .navigationTitle("检查文字").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) }
            }
            .tint(theme.accent)
        }
    }

    private func save() {
        var updated = page
        updated.lines = lines.map { draft in
            guard let before = page.lines.first(where: { $0.id == draft.id }) else { return draft }
            return before.applyingCorrection(draft.text)
        }
        if onSave(updated) { dismiss() }
    }
}

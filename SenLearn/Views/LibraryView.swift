import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var appearance: AppearanceSettings
    let onOpen: (UUID) -> Void
    let onAdd: () -> Void
    let onSample: () -> Void
    let onSettings: () -> Void
    @State private var removing: Book?
    @State private var renaming: Book?
    @State private var newTitle = ""
    private var theme: AppTheme { appearance.theme }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        LeafBrand(theme: theme)
                        Spacer()
                        RoundTool(title: "设置", symbol: "slider.horizontal.3", theme: theme, action: onSettings)
                            .accessibilityIdentifier("library.settings")
                    }
                    welcome(wide: geometry.size.width > 700)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("我的书架").font(.system(.title2, design: .rounded, weight: .bold))
                            Text(library.books.isEmpty ? "从一页喜欢的内容开始" : "\(library.books.count) 份材料 · 只保存在这台设备")
                                .font(.subheadline).foregroundStyle(theme.ink.opacity(0.6))
                        }
                        Spacer()
                        if !library.books.isEmpty {
                            Button(action: onAdd) { Label("添加材料", systemImage: "plus") }
                                .buttonStyle(SoftButtonStyle(theme: theme)).disabled(!library.isAvailable)
                        }
                    }
                    if library.books.isEmpty {
                        emptyLibrary
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 24)], alignment: .leading, spacing: 28) {
                            ForEach(library.books) { book in bookCard(book) }
                        }
                    }
                    Label("让好奇心翻开下一页", systemImage: "leaf")
                        .font(.footnote).foregroundStyle(theme.ink.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .foregroundStyle(theme.ink)
                .padding(geometry.size.width > 700 ? 42 : 22)
                .frame(maxWidth: 1400).frame(maxWidth: .infinity)
            }
        }
        .alert("移除这份材料？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("取消", role: .cancel) { removing = nil }
            Button("移除", role: .destructive) {
                guard let book = removing else { return }
                do { try library.deleteBook(id: book.id) } catch { library.errorMessage = error.localizedDescription }
                removing = nil
            }
        } message: { Text("「\(removing?.title ?? "")」及其识别结果将从本机移除，无法撤销。外部原文件不会被删除。") }
        .alert("修改书名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("书名", text: $newTitle)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                guard let book = renaming else { return }
                do { try library.renameBook(id: book.id, title: newTitle) } catch { library.errorMessage = error.localizedDescription }
                renaming = nil
            }
        }
    }

    private func welcome(wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
        return layout {
            VStack(alignment: .leading, spacing: 18) {
                Text("一 方 小 小 的 阅 读 森 林").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
                Text("每一页，\n都能听见。").font(.system(size: wide ? 43 : 34, weight: .semibold, design: .serif)).lineSpacing(5)
                Text("拍下喜欢的书页，轻点文字。\n和孩子一起，发现阅读里的小惊喜。")
                    .font(.body).foregroundStyle(theme.ink.opacity(0.7)).lineSpacing(6)
                Button(action: onAdd) { Label(library.books.isEmpty ? "添加第一份材料" : "添加新材料", systemImage: "plus") }
                    .buttonStyle(SoftButtonStyle(theme: theme, prominent: true))
                    .disabled(!library.isAvailable).accessibilityIdentifier("library.add")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image("forest-lesson").resizable().scaledToFit()
                .frame(maxWidth: wide ? 520 : .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
        }.padding(wide ? 32 : 24)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(theme.accent.opacity(0.09), lineWidth: 1))
    }

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical").font(.title2).foregroundStyle(theme.accent)
                Text("你的第一本点读书，正等着你").font(.headline)
            }
            Text("支持 PDF、照片和连续拍摄。\n也可以先读一页 Forest Friends，试试点读。")
                .font(.subheadline).foregroundStyle(theme.ink.opacity(0.65)).multilineTextAlignment(.center).lineSpacing(5)
            Button(action: onSample) { Label("试读示例", systemImage: "play.circle") }
                .buttonStyle(SoftButtonStyle(theme: theme)).disabled(!library.isAvailable)
                .accessibilityIdentifier("library.sample")
        }.padding(32).frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(theme.accent.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6])))
    }

    private func bookCard(_ book: Book) -> some View {
        Button { onOpen(book.id) } label: {
            VStack(alignment: .leading, spacing: 13) {
                ZStack {
                    Color.white
                    if let page = book.pages.first { PageThumbnail(url: library.imageURL(for: page)).padding(8) }
                }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 14))
                Text(book.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                HStack {
                    Text("\(book.pages.count) 页"); Spacer()
                    Text("继续第 \(book.currentPageIndex + 1) 页").foregroundStyle(theme.accent)
                }.font(.caption)
            }.padding(15).background(theme.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.accent.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("library.book.\(book.id)")
            .contextMenu {
                Button("修改书名", systemImage: "pencil") { newTitle = book.title; renaming = book }
                Button("移除材料", systemImage: "trash", role: .destructive) { removing = book }
            }
    }
}

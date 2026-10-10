import SwiftUI

struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var speech: SpeechPlayer
    let bookID: UUID
    let onBack: () -> Void
    let onSettings: () -> Void
    let onAppend: () -> Void
    @State private var selectedID: UUID?
    @State private var candidates: [RecognizedWord] = []
    @State private var lastSpokenText = ""
    @State private var recognizing = false
    @State private var recognitionGeneration = UUID()
    @State private var showingCorrections = false
    @State private var showingText = false
    @State private var confirmingRetry = false
    @Environment(\.scenePhase) private var scenePhase
    private let recognizer = TextRecognizer()

    private var theme: AppTheme { appearance.theme }
    private var book: Book? { library.book(id: bookID) }
    private var page: BookPage? {
        guard let book, book.pages.indices.contains(book.currentPageIndex) else { return nil }
        return book.pages[book.currentPageIndex]
    }
    private var word: RecognizedWord? { page?.lines.flatMap(\.words).first { $0.id == selectedID } }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header(wide: geometry.size.width > 760)
                if let book, let page {
                    HStack(spacing: 18) {
                        if appearance.parentPanel && geometry.size.width > 760 {
                            thumbnails(book: book).frame(width: 104)
                        }
                        ZStack(alignment: .top) {
                            WordPageCanvas(page: page, imageURL: library.imageURL(for: page), selectedID: selectedID,
                                           color: UIColor(theme.accent), reduceMotion: appearance.reduceMotion, onCandidates: choose)
                                .accessibilityLabel("第 \(book.currentPageIndex + 1) 页，双指缩放书页")
                            if recognizing {
                                Label { Text("正在识别第 \(book.currentPageIndex + 1) 页") } icon: { ProgressView().tint(theme.accent) }
                                    .font(.subheadline).padding(12).background(theme.surface, in: Capsule()).padding(.top, 12)
                            }
                        }
                    }.padding(.horizontal, geometry.size.width > 760 ? 26 : 12).padding(.top, 14)
                    if page.recognitionState == .failed {
                        HStack {
                            Label(page.recognitionError ?? "没有识别到文字，请尝试更清晰的页面。", systemImage: "text.magnifyingglass")
                                .font(.footnote).lineLimit(2)
                            Button("重试") { retryRecognition() }.font(.subheadline.bold())
                        }.padding(12).foregroundStyle(theme.ink)
                    }
                    if !candidates.isEmpty { candidateChooser }
                    playbackDock(page: page, book: book, narrow: geometry.size.width < 600)
                } else {
                    ContentUnavailableView("没有找到这本书", systemImage: "book.closed", description: Text("请返回书架重新打开。"))
                }
            }
        }
        .foregroundStyle(theme.ink)
        .task(id: page?.id) { await recognizeCurrentPage() }
        .onChange(of: page?.id) { _, _ in
            speech.stop(); selectedID = nil; candidates = []; lastSpokenText = ""
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { speech.stop() } }
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showingCorrections) {
            if let page { CorrectionView(page: page, imageURL: library.imageURL(for: page), theme: theme) { updated in
                do {
                    try library.updatePage(updated, in: bookID)
                    speech.stop(); selectedID = nil; lastSpokenText = ""
                    return true
                } catch { library.errorMessage = error.localizedDescription; return false }
            } }
        }
        .sheet(isPresented: $showingText) { textSheet }
        .alert("重新识别这一页？", isPresented: $confirmingRetry) {
            Button("取消", role: .cancel) {}
            Button("重新识别", role: .destructive) { retryRecognition() }
        } message: { Text("这会替换本页的识别结果和已校对文字，原始书页保持不变。") }
    }

    private func header(wide: Bool) -> some View {
        HStack(spacing: wide ? 20 : 8) {
            if wide { LeafBrand(theme: theme); Divider().frame(height: 28) }
            Button(action: onBack) {
                Label(wide ? "返回书架" : "书架", systemImage: "chevron.left")
                    .font(.system(.body, design: .rounded, weight: .medium)).frame(minHeight: 48)
            }.accessibilityIdentifier("reader.back")
            Spacer(minLength: 4)
            VStack(spacing: 3) {
                Text(book?.title ?? "阅读").font(.system(wide ? .title3 : .subheadline, design: .serif, weight: .semibold)).lineLimit(1)
                if let book {
                    Text("\(book.currentPageIndex + 1) / \(book.pages.count)").font(.caption).foregroundStyle(theme.ink.opacity(0.6))
                        .accessibilityIdentifier("reader.pageCounter")
                }
            }
            Spacer(minLength: 4)
            if wide {
                Label("点读", systemImage: "book").font(.subheadline.bold())
                    .padding(.horizontal, 19).padding(.vertical, 10).background(theme.softAccent, in: Capsule())
            }
            Menu {
                Button("继续添加书页", systemImage: "plus.rectangle.on.rectangle", action: onAppend)
                Button("检查文字", systemImage: "text.badge.checkmark") { speech.stop(); showingCorrections = true }
                    .disabled(page?.lines.isEmpty != false || recognizing)
                Button("文字列表", systemImage: "text.alignleft") { showingText = true }
                    .disabled(page?.lines.isEmpty != false)
                Button(appearance.parentPanel ? "收起页目录" : "显示页目录", systemImage: "sidebar.left") { appearance.parentPanel.toggle() }
                Button("重新识别本页", systemImage: "arrow.clockwise") { confirmingRetry = true }.disabled(recognizing)
            } label: {
                Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 48).contentShape(Rectangle())
            }.accessibilityLabel("家长辅助").accessibilityIdentifier("reader.more")
            RoundTool(title: "设置", symbol: "slider.horizontal.3", theme: theme, action: onSettings)
                .accessibilityIdentifier("reader.settings")
        }.padding(.horizontal, wide ? 26 : 14).padding(.vertical, 8)
            .background(theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.accent.opacity(0.08)).frame(height: 1) }
    }

    private func thumbnails(book: Book) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("页 目 录").font(.caption).foregroundStyle(theme.ink.opacity(0.5)).padding(.top, 12)
                ForEach(Array(book.pages.enumerated()), id: \.element.id) { index, item in
                    Button { turn(to: index) } label: {
                        VStack(spacing: 7) {
                            PageThumbnail(url: library.imageURL(for: item)).padding(5)
                                .frame(width: 96, height: 112).background(.white, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(index == book.currentPageIndex ? theme.accent : theme.accent.opacity(0.1), lineWidth: index == book.currentPageIndex ? 2 : 1))
                            Text("\(index + 1)").font(.caption.weight(index == book.currentPageIndex ? .bold : .regular))
                        }
                    }.buttonStyle(.plain).accessibilityLabel("第 \(index + 1) 页")
                }
                Button(action: onAppend) { Image(systemName: "plus").frame(width: 80, height: 44) }
                    .buttonStyle(.bordered).accessibilityLabel("继续添加书页")
            }
        }.scrollIndicators(.hidden)
    }

    private var candidateChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你想听哪个词？").font(.caption).foregroundStyle(theme.ink.opacity(0.7))
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(candidates) { candidate in
                        Button(candidate.text) { select(candidate) }.buttonStyle(SoftButtonStyle(theme: theme))
                    }
                    Button("收起") { candidates = [] }.frame(minWidth: 44, minHeight: 44)
                }
            }
        }.padding(.horizontal, 26).padding(.top, 8)
    }

    private func playbackDock(page: BookPage, book: Book, narrow: Bool) -> some View {
        VStack(spacing: narrow ? 10 : 12) {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap").foregroundStyle(theme.accent)
                if let word {
                    Text(word.text).font(.system(narrow ? .title3 : .title2, design: .serif, weight: .semibold)).lineLimit(1)
                        .accessibilityIdentifier("reader.selectedWord")
                } else {
                    Text(recognizing ? "书页马上准备好" : "点一点文字，听听怎么读")
                        .font(narrow ? .caption : .subheadline).foregroundStyle(theme.ink.opacity(0.65))
                }
                Spacer(minLength: 4)
                if speech.isSpeaking {
                    Button { speech.togglePause() } label: {
                        Image(systemName: speech.isPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(speech.isPaused ? "继续播放" : "暂停")
                    Button { speech.stop() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("停止")
                } else {
                    Menu {
                        ForEach([0.5, 0.7, 0.8, 1.0, 1.2], id: \.self) { value in
                            Button(String(format: "%.1f×", value)) { speech.rate = value }
                        }
                    } label: {
                        Text(String(format: "%.1f×", speech.rate)).font(.subheadline.bold()).frame(minWidth: 50, minHeight: 44)
                    }.accessibilityLabel("语速")
                }
            }.frame(minHeight: 34)
            HStack(spacing: narrow ? 8 : 16) {
                actionButton("听单词", symbol: "speaker.wave.2.fill", color: theme.accent, ink: theme.onAccent,
                             enabled: word != nil, narrow: narrow) { if let word { speak(word.text) } }
                    .accessibilityIdentifier("reader.word")
                actionButton("听整句", symbol: "text.bubble", color: theme == .night ? theme.softAccent : Color(red: 0.74, green: 0.85, blue: 0.89),
                             ink: theme == .night ? theme.ink : Color(red: 0.14, green: 0.25, blue: 0.28), enabled: word != nil, narrow: narrow) {
                    if let word { speak(TextRecognizer.sentence(containing: word.id, in: page.lines)) }
                }.accessibilityIdentifier("reader.sentence")
                actionButton("再听一次", symbol: "arrow.counterclockwise", color: theme == .night ? theme.surface : Color(red: 0.96, green: 0.83, blue: 0.50),
                             ink: theme == .night ? theme.ink : Color(red: 0.27, green: 0.21, blue: 0.12), enabled: !lastSpokenText.isEmpty, narrow: narrow) {
                    speak(lastSpokenText)
                }.accessibilityIdentifier("reader.replay")
            }
            HStack(spacing: 14) {
                Button { turn(to: book.currentPageIndex - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(book.currentPageIndex == 0).accessibilityLabel("上一页").accessibilityIdentifier("reader.previous")
                Text("\(book.currentPageIndex + 1) / \(book.pages.count)").font(.subheadline).monospacedDigit()
                Button { turn(to: book.currentPageIndex + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(book.currentPageIndex + 1 >= book.pages.count).accessibilityLabel("下一页").accessibilityIdentifier("reader.next")
                Spacer()
                Button { speak(page.text) } label: { Label("听整页", systemImage: "play.circle").font(.subheadline).frame(minHeight: 44) }
                    .disabled(page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.foregroundStyle(theme.accent)
            if let status = speech.statusMessage {
                Text(status).font(.caption).foregroundStyle(theme.ink.opacity(0.7)).accessibilityIdentifier("reader.speechStatus")
            }
        }
        .padding(.horizontal, narrow ? 18 : 28).padding(.top, narrow ? 8 : 12).padding(.bottom, 4)
        .frame(maxWidth: 1000).frame(maxWidth: .infinity)
    }

    private func actionButton(_ title: String, symbol: String, color: Color, ink: Color, enabled: Bool,
                              narrow: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: narrow ? 6 : 14) {
                Image(systemName: symbol).font(.system(size: narrow ? 18 : 26, weight: .medium))
                Text(title).font(.system(narrow ? .subheadline : .title3, design: .rounded, weight: .bold))
            }.frame(maxWidth: .infinity, minHeight: narrow ? 58 : 72)
                .foregroundStyle(ink).background(color.opacity(enabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain).disabled(!enabled)
    }

    private var textSheet: some View {
        NavigationStack {
            List {
                Section { Text("点击一行听读。校对过的文字在这里也可以朗读。").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(page?.lines ?? []) { line in
                    Button { speak(line.text) } label: {
                        HStack { Text(line.text).foregroundStyle(.primary); Spacer(); Image(systemName: "speaker.wave.2") }.padding(.vertical, 8)
                    }
                }
            }.navigationTitle("本页文字").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingText = false } } }
        }
    }

    private func choose(_ words: [RecognizedWord]) {
        if words.count == 1, let word = words.first { select(word) }
        else { speech.stop(); candidates = words }
    }

    private func select(_ word: RecognizedWord) {
        selectedID = word.id; candidates = []; speak(word.text)
    }
    private func speak(_ text: String) { lastSpokenText = text; speech.speak(text) }

    private func turn(to index: Int) {
        guard let book, book.pages.indices.contains(index) else { return }
        speech.stop()
        do { try library.setReadingPosition(bookID: bookID, index: index) }
        catch { library.errorMessage = error.localizedDescription }
    }

    private func retryRecognition() {
        guard var page else { return }
        page.recognitionState = .pending; page.recognitionError = nil
        page.lines = []; selectedID = nil; lastSpokenText = ""; speech.stop()
        do {
            try library.updatePage(page, in: bookID)
            Task { await recognizeCurrentPage() }
        } catch { library.errorMessage = error.localizedDescription }
    }

    private func recognizeCurrentPage() async {
        guard var current = page, current.recognitionState == .pending else { return }
        let generation = UUID(); recognitionGeneration = generation; recognizing = true
        defer { if recognitionGeneration == generation { recognizing = false } }
        do {
            let lines = try await recognizer.recognize(imageURL: library.imageURL(for: current))
            try Task.checkCancellation()
            current.lines = lines
            current.recognitionState = lines.isEmpty ? .failed : .ready
            current.recognitionError = lines.isEmpty ? "没有识别到文字，请重新拍摄清晰、平整的书页。" : nil
            try library.updatePage(current, in: bookID)
        } catch is CancellationError {
            // Leave the page pending; returning to it starts a fresh recognition request.
        } catch {
            current.recognitionState = .failed; current.recognitionError = error.localizedDescription
            do { try library.updatePage(current, in: bookID) } catch { library.errorMessage = error.localizedDescription }
        }
    }
}

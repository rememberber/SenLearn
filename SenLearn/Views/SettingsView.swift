import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var speech: SpeechPlayer
    @State private var showingLicenses = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var theme: AppTheme { appearance.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    introduction
                    themeSection
                    readingSection
                    soundSection
                }
                .frame(maxWidth: 760)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("settings.scroll")
            .background(theme.background)
            .foregroundStyle(theme.ink)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .sheet(isPresented: $showingLicenses) { SpeechLicensesView() }
        .tint(theme.accent)
        .preferredColorScheme(theme == .night ? .dark : .light)
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 60, height: 60)
                .background(theme.softAccent, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("舒服地读，慢慢地学")
                    .font(.title3.weight(.semibold))
                Text("为每一次共读，选一个喜欢的样子。")
                    .font(.subheadline)
                    .foregroundStyle(theme.ink.opacity(0.72))
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("外观主题", icon: "paintpalette")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        if systemReduceMotion || appearance.reduceMotion {
                            appearance.theme = option
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) { appearance.theme = option }
                        }
                    } label: {
                        ThemeOptionCard(theme: option, selected: theme == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(option.name + (option == .forest ? "，默认主题" : ""))
                    .accessibilityValue(theme == option ? "已选中" : "未选中")
                    .accessibilityAddTraits(theme == option ? .isSelected : [])
                    .accessibilityHint("选择后立即应用并保存在本机")
                    .accessibilityIdentifier("settings.theme.\(option.rawValue)")
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Text("教材保留原来的颜色。主题会自动保存。")
                    .font(.footnote)
                    .foregroundStyle(theme.ink.opacity(0.7))
                Spacer(minLength: 0)
            }
            Button("恢复默认主题") { appearance.resetTheme() }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .disabled(theme == .forest)
                .accessibilityHint("只恢复森间书桌主题，保留其他阅读设置")
        }
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("阅读偏好", icon: "book")
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("朗读语速").font(.body.weight(.semibold))
                        Spacer()
                        Text(speech.rate.formatted(.number.precision(.fractionLength(1))) + "×")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.accent)
                    }
                    Slider(value: $speech.rate, in: 0.5...1.2, step: 0.1)
                        .accessibilityLabel("朗读语速")
                        .accessibilityValue(speech.rate.formatted(.number.precision(.fractionLength(1))) + "倍")
                    HStack {
                        Text("慢一点")
                        Spacer()
                        Text("快一点")
                    }
                    .font(.caption)
                    .foregroundStyle(theme.ink.opacity(0.7))
                    Text("调整后，在下一次播放时生效。")
                        .font(.footnote)
                        .foregroundStyle(theme.ink.opacity(0.7))
                }
                Divider().overlay(theme.ink.opacity(0.06))
                Toggle(isOn: $appearance.parentPanel) {
                    preferenceLabel("家长辅助面板", detail: "阅读时显示页目录和文字检查工具。")
                }
                .accessibilityIdentifier("settings.parentPanel")
                Divider().overlay(theme.ink.opacity(0.06))
                Toggle(isOn: $appearance.reduceMotion) {
                    preferenceLabel("减少动态效果", detail: systemReduceMotion ? "已跟随系统减少动态效果。" : "让主题切换与阅读反馈更安静。")
                }
                .accessibilityIdentifier("settings.reduceMotion")
            }
            .padding(20)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius))
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("朗读声音", icon: "speaker.wave.2")
            VStack(alignment: .leading, spacing: 12) {
                Picker("朗读方式", selection: $speech.engine) {
                    ForEach(SpeechEngine.allCases) { engine in Text(engine.name).tag(engine) }
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.speechEngine")
                if speech.engine == .kokoro {
                    Picker("声音风格", selection: $speech.voiceStyle) {
                        ForEach(SpeechVoiceStyle.allCases) { style in Text(style.name).tag(style) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("settings.voiceStyle")
                    Text(speech.voiceStyle.detail)
                        .font(.footnote).foregroundStyle(theme.ink.opacity(0.72))
                }
                Text(speech.voiceAvailabilitySummary)
                    .font(.subheadline)
                Text(speech.engine == .kokoro ? "中文与英文随文字自动切换。声音在本机生成，无需下载或联网。" : "使用设备提供的声音；可用声音取决于系统配置。")
                    .font(.footnote)
                    .foregroundStyle(theme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("试听中文") { speech.speak("小松鼠在森林里找到了一个种子。") }
                        .accessibilityIdentifier("settings.testChinese")
                    Button("试听英文") { speech.speak("The little squirrel lives in the forest.") }
                        .accessibilityIdentifier("settings.testEnglish")
                }.buttonStyle(SoftButtonStyle(theme: theme))
                if speech.isSpeaking {
                    Button("停止试听") { speech.stop() }.frame(minHeight: 44)
                }
                if let status = speech.statusMessage { Text(status).font(.footnote) }
                if speech.engine == .kokoro, let summary = speech.synthesisSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.synthesisSummary")
                }
                Button("开源组件与许可") { showingLicenses = true }.font(.footnote).frame(minHeight: 44)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius))
        }
    }

    private func sectionHeading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(theme.ink)
    }

    private func preferenceLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.body.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(theme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct ThemeOptionCard: View {
    let theme: AppTheme
    let selected: Bool

    private var symbol: String {
        switch theme {
        case .forest: "leaf.fill"
        case .native: "book.closed.fill"
        case .play: "sun.max.fill"
        case .night: "moon.stars.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .padding(14)
                .background(theme.background)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(theme.name).font(.headline)
                    if theme == .forest {
                        Text("默认")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(theme.softAccent, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? theme.accent : theme.ink.opacity(0.3))
                }
                Text(theme.subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(theme.ink)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius)
                .strokeBorder(selected ? theme.accent : theme.ink.opacity(0.12), lineWidth: selected ? 2.5 : 1)
        }
    }

    private var preview: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill").font(.system(size: 10))
                Text("SenLearn").font(.system(size: 10, weight: .semibold, design: .serif))
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 13))
            }
            .foregroundStyle(theme.accent)
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(theme.accent)
                    .frame(width: 62, height: 66)
                    .background(theme.softAccent, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 7) {
                    Text("Let's read.")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Color(red: 0.14, green: 0.23, blue: 0.2))
                    Capsule().fill(theme.softAccent).frame(width: 74, height: 7)
                    Capsule().fill(Color.gray.opacity(0.15)).frame(width: 54, height: 5)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(red: 1, green: 0.992, blue: 0.969), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 7) {
                previewButton("speaker.wave.2.fill", primary: true)
                previewButton("text.bubble.fill", primary: false)
                previewButton("arrow.counterclockwise", primary: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func previewButton(_ symbol: String, primary: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 25)
            .foregroundStyle(primary ? theme.onAccent : theme.ink)
            .background(primary ? theme.accent : theme.softAccent, in: Capsule())
    }
}

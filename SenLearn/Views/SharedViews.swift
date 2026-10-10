import SwiftUI

struct LeafBrand: View {
    var theme: AppTheme
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "leaf.fill").font(.system(size: 23, weight: .medium)).foregroundStyle(theme.accent)
            Text("SenLearn").font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(theme.ink)
        }.accessibilityElement(children: .combine)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var theme: AppTheme
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .padding(.horizontal, 20).padding(.vertical, 15)
            .foregroundStyle(prominent ? theme.onAccent : theme.accent)
            .background(prominent ? theme.accent : theme.softAccent, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct RoundTool: View {
    let title: String
    let symbol: String
    let theme: AppTheme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .foregroundStyle(theme.accent)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct PageThumbnail: View {
    let url: URL
    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "doc.richtext").resizable().scaledToFit().padding(30)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

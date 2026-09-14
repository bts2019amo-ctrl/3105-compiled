import SwiftUI

enum AppTheme {
    private static var remoteAccent: Color?
    static var accent: Color {
        get {
            remoteAccent ?? (UserDefaults.standard.string(forKey: "externalTheme") == "white"
                ? .white
                : Color(uiColor: UIColor(red: 0.64, green: 0.31, blue: 0.98, alpha: 1.00)))
        }
        set { remoteAccent = newValue }
    }
    static var secondaryAccent = Color.white
    static var pageBackground = Color(uiColor: UIColor(red: 0.055, green: 0.04, blue: 0.09, alpha: 1.00))
    static let consoleBackground = Color(uiColor: UIColor(red: 0.09, green: 0.07, blue: 0.14, alpha: 1.00))
    static let glassBase = Color(uiColor: UIColor(red: 0.11, green: 0.08, blue: 0.16, alpha: 1.00))
    static let glassHighlight = Color.white.opacity(0.42)
    static let glassShadow = Color.black.opacity(0.12)
    static let pageInset: CGFloat = 20
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 24
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16

    static var pageGradient: LinearGradient {
        LinearGradient(
            colors: [
                pageBackground,
                accent.opacity(0.055),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LiquidGlassRootModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.1, *) {
            content
                .fontDesign(.rounded)
                .tint(AppTheme.accent)
                .background(AppTheme.pageGradient.ignoresSafeArea())
        } else {
            content
                .tint(AppTheme.accent)
                .background(AppTheme.pageGradient.ignoresSafeArea())
        }
    }
}

extension View {
    func liquidGlassRoot() -> some View {
        modifier(LiquidGlassRootModifier())
    }
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(0.72), AppTheme.accent.opacity(0.24), Color.white.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.8
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}

struct AppGlassRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    colors: [AppTheme.glassHighlight, .clear, AppTheme.accent.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.68), AppTheme.accent.opacity(0.18), Color.white.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: AppTheme.glassShadow, radius: 14, y: 7)
            .padding(.vertical, 4)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(tint.opacity(0.22), lineWidth: 0.6)
                        }
                }
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 0.7)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

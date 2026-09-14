import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @AppStorage("externalTheme") private var theme = "purple"
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = true
    @AppStorage(FeatureVisibility.developerModeStorageKey) private var developerModeEnabled = false

    private var themeAccent: Color { theme == "white" ? .white : AppTheme.accent }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    settingsHero
                    settingsSection(title: "APPEARANCE") {
                        themeRow
                        preferenceRow(icon: "circle.lefthalf.filled", title: "Interface style", subtitle: theme == "white" ? "White" : "Purple") {
                            Menu {
                                Button { theme = "purple" } label: { Label("Purple", systemImage: theme == "purple" ? "checkmark" : "paintpalette") }
                                Button { theme = "white" } label: { Label("White", systemImage: theme == "white" ? "checkmark" : "circle.fill") }
                                Button { theme = "blue" } label: { Label("Blue", systemImage: theme == "blue" ? "checkmark" : "circle.fill") }
                                Button { theme = "cyan" } label: { Label("Cyan", systemImage: theme == "cyan" ? "checkmark" : "circle.fill") }
                                Button { theme = "green" } label: { Label("Green", systemImage: theme == "green" ? "checkmark" : "circle.fill") }
                                Button { theme = "orange" } label: { Label("Orange", systemImage: theme == "orange" ? "checkmark" : "circle.fill") }
                                Button { theme = "red" } label: { Label("Red", systemImage: theme == "red" ? "checkmark" : "circle.fill") }
                                Button { theme = "pink" } label: { Label("Pink", systemImage: theme == "pink" ? "checkmark" : "circle.fill") }
                            } label: {
                                HStack(spacing: 4) { Text(theme == "white" ? "White" : "Purple"); Image(systemName: "chevron.up.chevron.down") }
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(themeAccent)
                            }
                        }
                    }
                    settingsSection(title: "APP BEHAVIOR") {
                        ToggleRow(icon: "sparkles", title: "Cleaner", subtitle: "Show temporary file cleanup", isOn: $cleanerEnabled, tint: themeAccent)
                        ToggleRow(icon: "hammer.fill", title: "Developer mode", subtitle: "Reveal advanced local tools", isOn: $developerModeEnabled, tint: themeAccent)
                    }
                    settingsSection(title: "DEVICE") {
                        infoRow(icon: "iphone", title: "Device", value: AppInfo.displayMachineName)
                        infoRow(icon: "apple.logo", title: "System", value: "iOS \(AppInfo.osVersion)")
                        infoRow(icon: "checkmark.shield.fill", title: "Compatibility", value: appState.isSupported ? "Supported" : "Unsupported", valueColor: appState.isSupported ? .green : .red)
                    }
                    settingsSection(title: "ABOUT") {
                        infoRow(icon: "number", title: "Version", value: appVersion)
                        HStack(spacing: 10) { Image(systemName: "lock.shield.fill").foregroundStyle(themeAccent); Text("Secure local workspace").font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "checkmark").foregroundStyle(.green) }
                            .padding(.vertical, 4)
                    }
                    HStack { Spacer(); Text("EXTERNAL iOS · SECURE · SIMPLE · READY").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary); Spacer() }.padding(.top, 5)
                }
                    .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold).foregroundStyle(themeAccent) } }
            .tint(themeAccent)
            .liquidGlassRoot()
        }
    }

    private var settingsHero: some View {
        HStack(spacing: 14) {
            AppLogo(size: 62)
            VStack(alignment: .leading, spacing: 5) { Text("EXTERNAL iOS").font(.title3.weight(.bold)); Text("Personalize your secure workspace").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(themeAccent.opacity(0.3), lineWidth: 0.8) }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary).padding(.horizontal, 5); VStack(spacing: 0, content: content).padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 0.7) } }
    }

    private var themeRow: some View {
        HStack(spacing: 11) {
            ZStack { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(themeAccent.opacity(0.15)); Image(systemName: "paintbrush.fill").foregroundStyle(themeAccent) }.frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 3) { Text("Accent theme").font(.subheadline.weight(.semibold)); Text("Change the visual accent color").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Menu {
                Button { theme = "purple" } label: { Label("Purple", systemImage: theme == "purple" ? "checkmark" : "paintpalette") }
                Button { theme = "white" } label: { Label("White", systemImage: theme == "white" ? "checkmark" : "circle.fill") }
                Button { theme = "blue" } label: { Label("Blue", systemImage: theme == "blue" ? "checkmark" : "circle.fill") }
                Button { theme = "cyan" } label: { Label("Cyan", systemImage: theme == "cyan" ? "checkmark" : "circle.fill") }
                Button { theme = "green" } label: { Label("Green", systemImage: theme == "green" ? "checkmark" : "circle.fill") }
                Button { theme = "orange" } label: { Label("Orange", systemImage: theme == "orange" ? "checkmark" : "circle.fill") }
                Button { theme = "red" } label: { Label("Red", systemImage: theme == "red" ? "checkmark" : "circle.fill") }
                Button { theme = "pink" } label: { Label("Pink", systemImage: theme == "pink" ? "checkmark" : "circle.fill") }
            } label: { Circle().fill(themeAccent).frame(width: 22, height: 22).overlay { Circle().stroke(Color.white.opacity(0.45), lineWidth: 1) } }
        }
        .padding(.vertical, 8)
    }

    private func preferenceRow(icon: String, title: String, subtitle: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 11) { AppRowIcon(systemName: icon, tint: themeAccent); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); action() }.padding(.vertical, 8)
    }

    private func infoRow(icon: String, title: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack(spacing: 11) { AppRowIcon(systemName: icon, tint: themeAccent); Text(title).font(.subheadline.weight(.semibold)); Spacer(); Text(value).font(.caption).foregroundStyle(valueColor).lineLimit(1) }.padding(.vertical, 8)
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let tint: Color
    var body: some View { HStack(spacing: 11) { AppRowIcon(systemName: icon, tint: tint); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("", isOn: $isOn).labelsHidden().tint(tint).toggleStyle(LiquidGlassToggleStyle()) }.padding(.vertical, 8) }
}

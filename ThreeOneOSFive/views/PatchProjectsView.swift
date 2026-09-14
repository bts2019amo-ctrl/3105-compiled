import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

private enum WallpaperPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "tendies") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var store: PatchProjectStore
    @EnvironmentObject private var remoteControl: RemoteControlService
    @State private var showCreate = false
    @State private var wallpaperPackages: [WallpaperStagedPackage] = []
    @State private var wallpaperImportFeedback: WallpaperImportFeedback?
    @State private var wallpaperPendingDeletion: WallpaperStagedPackage?
    @State private var isImportingWallpapers = false
    @State private var showSimulatedWallpaperDetail = false
    @State private var simulatedWallpaperDetailGate = OneShotPresentationGate()
    @State private var showThemeMenu = false
    @State private var showExternalPanel = false
    @State private var selectedCollection = "FF NORMAL"
    @AppStorage("externalTheme") private var externalTheme = "purple"
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    private var filteredItems: [PatchLibraryItem] {
        store.items
    }

    private var filteredWallpaperPackages: [WallpaperStagedPackage] {
        wallpaperPackages
    }

    private var remotePatchesForSelection: [RemotePatchInfo] {
        remoteControl.patchCatalog.filter { patch in
            let value = "\(patch.game) \(patch.target) \(patch.category)".uppercased()
            return selectedCollection == "FF MAX"
                ? value.contains("MAX")
                : !value.contains("MAX")
        }
    }

    private var hasLocalContent: Bool {
        !store.items.isEmpty
            || !wallpaperPackages.isEmpty
            || !remotePatchesForSelection.isEmpty
    }

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    selectionCard
                    compatibilityCard
                    if hasLocalContent {
                        installedContentCard
                    } else {
                        emptyInstalledCard
                    }
                    footerSignature
                }
                .padding(.horizontal, AppTheme.pageInset)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(Color.clear)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            showThemeMenu.toggle()
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.42), lineWidth: 0.8))
                            .shadow(color: AppTheme.accent.opacity(0.18), radius: 10, y: 4)
                            .rotationEffect(.degrees(showThemeMenu ? 28 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Configurações de aparência")
                    .popover(isPresented: $showThemeMenu, arrowEdge: .top) {
                        ThemeSelectionPopover(
                            selectedTheme: $externalTheme,
                            onClose: { showThemeMenu = false }
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            showExternalPanel = true
                        }
                    } label: {
                        Label("EXTERNAL", systemImage: "scope")
                            .font(.caption.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Abrir EXTERNAL")
                }
                ToolbarItem(placement: .navigationBarLeading) { Text("EXTERNAL iOS").font(.headline.weight(.bold)) }
            }
            .sheet(isPresented: $showCreate) {
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false
                ) { project, password in
                    store.create(project: project, password: password)
                }
            }
            .sheet(isPresented: $showExternalPanel) {
                ExternalPanelView()
                    .environmentObject(remoteControl)
            }
            .sheet(item: $draftCoordinator.request) { request in
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false,
                    initialDraft: request.draft
                ) { project, password in
                    store.create(project: project, password: password)
                    draftCoordinator.clear()
                }
            }
            .alert(item: $wallpaperImportFeedback) { feedback in
                Alert(
                    title: Text(language.text(feedback.titleKey)),
                    message: Text(feedback.message),
                    dismissButton: .default(Text(language.text("common.ok")))
                )
            }
            .alert(item: $wallpaperPendingDeletion) { package in
                Alert(
                    title: Text(language.text("wallpaper.delete_title")),
                    message: Text(language.text(
                        "wallpaper.delete_message",
                        package.displayName
                    )),
                    primaryButton: .destructive(
                        Text(language.text("common.delete"))
                    ) {
                        deleteWallpaperPackage(package)
                    },
                    secondaryButton: .cancel(Text(language.text("common.cancel")))
                )
            }
            .onAppear {
                reloadWallpaperPackages()
                consumeExternalImport()
#if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains(
                    "--simulate-wallpaper-detail"
                ), !wallpaperPackages.isEmpty,
                   simulatedWallpaperDetailGate.claim() {
                    DispatchQueue.main.async {
                        showSimulatedWallpaperDetail = true
                    }
                }
#endif
            }
            .navigationDestination(isPresented: $showSimulatedWallpaperDetail) {
                if let package = wallpaperPackages.first {
                    InstalledWallpaperPackageDetailView(
                        package: package,
                        onApplied: reloadWallpaperPackages
                    )
                }
            }
            .onChange(of: draftCoordinator.importRequest?.id) { _ in
                consumeExternalImport()
            }
        }
    }

    private var installedHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(AppTheme.accent.opacity(0.18))
                Image(systemName: "crown.fill").foregroundStyle(AppTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("EXTERNAL iOS").font(.title3.weight(.bold))
                Text("INSTALLED").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
        }
    }

    private var accessBanner: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.accent.opacity(0.84), Color.black.opacity(0.72)], startPoint: .topTrailing, endPoint: .bottomLeading))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.8) }
            Circle().fill(Color.white.opacity(0.12)).frame(width: 210, height: 210).blur(radius: 2).offset(x: 180, y: -90)
            VStack(alignment: .leading, spacing: 7) {
                Label("SECURE WORKSPACE", systemImage: "sparkles")
                    .font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(.white.opacity(0.82))
                Text("MORE THAN INSTALLED.\nYOUR CONTROL CENTER.")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(20)
        }
        .frame(height: 138)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.18), radius: 20, y: 9)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("SELECT COLLECTION", systemImage: "square.grid.2x2.fill").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                collectionButton(title: "FF NORMAL", icon: "gamecontroller.fill")
                collectionButton(title: "FF MAX", icon: "gamecontroller.fill")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private func collectionButton(title: String, icon: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { selectedCollection = title } } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.subheadline)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if selectedCollection == title { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent) }
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(selectedCollection == title ? AppTheme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: selectedCollection)
    }

    private var compatibilityCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("iOS \(AppInfo.osVersion)").font(.subheadline.weight(.bold))
                Text(appStateText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("SUPPORTED").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.green)
        }
        .padding(15)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.green.opacity(0.32), lineWidth: 0.8) }
    }

    private var appStateText: String { hasLocalContent ? "Installed content ready" : "Ready for your first install" }

    private var installedContentCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedCollection).font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.bottom, 5)
            if !remotePatchesForSelection.isEmpty {
                ForEach(remotePatchesForSelection, id: \.id) { patch in
                    remotePatchRow(patch).padding(.vertical, 5)
                }
            } else if selectedCollection == "FF MAX" {
                ForEach(filteredWallpaperPackages) { package in wallpaperRow(package).padding(.vertical, 5) }
            } else {
                ForEach(filteredItems) { item in itemRow(item).padding(.vertical, 5) }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.8) }
        .shadow(color: AppTheme.glassShadow, radius: 16, y: 8)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selectedCollection)
    }

    private var emptyInstalledCard: some View {
        VStack(spacing: 11) {
            Image(systemName: "tray.full.fill").font(.system(size: 28)).foregroundStyle(AppTheme.accent)
            Text("Nothing installed yet").font(.headline)
            Text("No installed content is available yet.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private var footerSignature: some View { HStack { Text("EXTERNAL iOS").font(.caption2.weight(.bold)).tracking(1.1); Spacer(); Text("SECURE · SIMPLE · READY").font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(.secondary) }.foregroundStyle(AppTheme.accent).padding(.top, 5) }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }

    private func remotePatchRow(_ patch: RemotePatchInfo) -> some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: "shippingbox.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(patch.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(patch.category) · \(patch.game)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { remoteControl.isPatchActive(patch) },
                set: { remoteControl.setPatchActive(patch, active: $0) }
            ))
            .labelsHidden()
            .toggleStyle(LiquidGlassToggleStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.glassBase.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func wallpaperRow(_ package: WallpaperStagedPackage) -> some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: wallpaperSymbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(package.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                InstalledContentKindBadge(kind: .wallpaper, language: language)
                Text(language.text(
                    "wallpaper.package_summary",
                    Int64(package.payload.descriptors.count),
                    ByteCountFormatter.string(
                        fromByteCount: package.payload.totalBytes,
                        countStyle: .file
                    )
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var wallpaperSymbol: String {
        if #available(iOS 18.0, *) {
            return "photo.on.rectangle.angled.fill"
        }
        return "photo.fill.on.rectangle.fill"
    }

    private func reloadWallpaperPackages() {
        wallpaperPackages = WallpaperPackageStore.packages()
    }

    private func deleteWallpaperPackage(_ package: WallpaperStagedPackage) {
        do {
            try WallpaperPackageStore.delete(package)
            reloadWallpaperPackages()
        } catch {
            wallpaperImportFeedback = WallpaperImportFeedback(
                titleKey: "wallpaper.operation_failed",
                message: wallpaperErrorMessage(error)
            )
        }
    }

    private func importWallpaperPackages(_ urls: [URL]) {
        guard !isImportingWallpapers else { return }
        isImportingWallpapers = true
        DispatchQueue.global(qos: .userInitiated).async {
            var imported = 0
            var failures: [String] = []
            for url in urls {
                do {
                    _ = try WallpaperPackageStore.importPackage(from: url)
                    imported += 1
                    log("wallpaper: staged \(url.lastPathComponent)")
                } catch {
                    failures.append(
                        "\(url.lastPathComponent): \(wallpaperErrorMessage(error))"
                    )
                    log("wallpaper: import rejected \(url.lastPathComponent)")
                }
            }
            DispatchQueue.main.async {
                isImportingWallpapers = false
                reloadWallpaperPackages()
                wallpaperImportFeedback = WallpaperImportFeedback(
                    titleKey: failures.isEmpty
                        ? "wallpaper.import_done_title"
                        : "wallpaper.import_result_title",
                    message: failures.isEmpty
                        ? language.text(
                            "wallpaper.import_done_message",
                            Int64(imported)
                        )
                        : failures.joined(separator: "\n")
                )
            }
        }
    }

    private func wallpaperErrorMessage(_ error: Error) -> String {
        if let wallpaperError = error as? WallpaperLabError {
            return language.text(wallpaperError.localizationKey)
        }
        return language.text("wallpaper.error.unknown")
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        PatchProjectRow(item: item, language: language)
            .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text(language.text("installed.empty_title"))
                .font(.headline)
            Text(language.text("installed.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(language.text("installed.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("patch.search_empty"))
                .font(.headline)
            Text(language.text("patch.search_empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

private struct ThemeSelectionPopover: View {
    @Binding var selectedTheme: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aparência")
                        .font(.headline.weight(.bold))
                    Text("Escolha o acabamento do Liquid Glass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "wand.and.stars")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            themeOption(
                title: "Roxo",
                subtitle: "Glass vibrante",
                value: "purple",
                tint: AppTheme.accent,
                icon: "sparkles"
            )
            themeOption(
                title: "Branco",
                subtitle: "Glass claro",
                value: "white",
                tint: .white,
                icon: "sun.max.fill"
            )
            HStack(spacing: 10) {
                colorDot("blue", .blue, "Azul")
                colorDot("cyan", .cyan, "Ciano")
                colorDot("green", .green, "Verde")
                colorDot("orange", .orange, "Laranja")
                colorDot("red", .red, "Vermelho")
                colorDot("pink", .pink, "Rosa")
            }
        }
        .padding(18)
        .frame(width: 286)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.72), AppTheme.accent.opacity(0.24), Color.white.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .shadow(color: AppTheme.accent.opacity(0.2), radius: 22, y: 10)
    }

    private func themeOption(
        title: String,
        subtitle: String,
        value: String,
        tint: Color,
        icon: String
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                selectedTheme = value
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(value == "white" ? 0.2 : 0.28))
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selectedTheme == value ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedTheme == value ? AppTheme.accent : .secondary)
                    .scaleEffect(selectedTheme == value ? 1 : 0.88)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(
                selectedTheme == value ? AppTheme.accent.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selectedTheme == value
                            ? AppTheme.accent.opacity(0.36)
                            : Color.white.opacity(0.16),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: selectedTheme)
    }

    private func colorDot(_ value: String, _ color: Color, _ label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                selectedTheme = value
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Circle()
                .fill(color)
                .frame(width: 27, height: 27)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: selectedTheme == value ? 2.2 : 0.8)
                }
                .overlay {
                    if selectedTheme == value {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: color.opacity(0.45), radius: selectedTheme == value ? 6 : 0)
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: selectedTheme)
    }
}

private struct WallpaperImportFeedback: Identifiable {
    let id = UUID()
    let titleKey: String
    let message: String
}

private struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: item.isLocked ? "lock.doc.fill" : "shippingbox.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                InstalledContentKindBadge(kind: .patch, language: language)
                if let author = item.project?.author, !author.isEmpty {
                    Text(language.text("patch.by_author", author))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.summary.isPasswordProtected {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
            if item.project?.isPrivate == true {
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(language.text("patch.private"))
            }
        }
        .padding(.vertical, 4)
    }

    private var rowDetail: String {
        if item.isLocked {
            return language.text("patch.tap_to_unlock")
        }
        if item.project?.isPrivate == true, !item.isAuthorCopy {
            return language.text("patch.private_received")
        }
        return language.text(
            item.summary.schemaVersion >= 2
                ? "patch.workspace_items_count"
                : "patch.rules_count",
            Int64((item.project?.rules.count ?? 0) + (item.project?.directories.count ?? 0))
        )
    }
}

private enum InstalledContentKind {
    case patch
    case wallpaper

    var localizationKey: String {
        switch self {
        case .patch: return "installed.kind.patch"
        case .wallpaper: return "installed.kind.wallpaper"
        }
    }

    var systemImage: String {
        switch self {
        case .patch: return "shippingbox.fill"
        case .wallpaper: return "photo.fill"
        }
    }
}

private struct InstalledContentKindBadge: View {
    let kind: InstalledContentKind
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .accessibilityHidden(true)
            Text(language.text(kind.localizationKey))
        }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(AppTheme.accent.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .combine)
    }
}

struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    let request: PatchPasswordRequest
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    if let origin = request.origin {
                        Text(language.text(
                            "patch.password_repo_contact",
                            origin.repositoryName
                        ))
                    } else {
                        Text(language.text("patch.password_once_message"))
                    }
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

private struct PatchStorePresentationModifier: ViewModifier {
    @ObservedObject var store: PatchProjectStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { request in
                PatchUnlockView(store: store, request: request)
            }
    }
}

extension View {
    func patchStorePresentation(_ store: PatchProjectStore) -> some View {
        modifier(PatchStorePresentationModifier(store: store))
    }
}

private struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showChangedRestoreConfirmation = false
    @State private var showResetConfirmation = false
    @State private var restoreChangedPaths: [String] = []
    @State private var isWorking = false
    @State private var actionAlert: PatchStoreAlert?
    @State private var shareRequest: PatchShareRequest?

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: projectID)
    }

    private var isWorkspaceProject: Bool {
        (item?.summary.schemaVersion ?? 1) >= 2
    }

    var body: some View {
        List {
            if let item, let project = item.project {
                Section(language.text("patch.information")) {
                    if !project.author.isEmpty {
                        patchInfoRow(
                            label: language.text("patch.author"),
                            value: project.author
                        )
                    }
                    patchInfoRow(label: language.text("patch.privacy")) {
                        Label(
                            language.text(project.isPrivate
                                ? "patch.private"
                                : "patch.public"),
                            systemImage: project.isPrivate
                                ? "eye.slash.fill"
                                : "eye"
                        )
                        .foregroundStyle(project.isPrivate ? AppTheme.accent : Color.secondary)
                    }
                    if let origin = item.origin {
                        patchInfoRow(
                            label: language.text("repository.source"),
                            value: origin.repositoryName
                        )
                    }
                }

                if project.isPrivate && !item.canInspectContents {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                            Text(language.text("patch.private_hidden_title"))
                                .font(.headline)
                            Text(language.text("patch.private_hidden_message"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else if isWorkspaceProject {
                    Section {
                        ForEach(project.allBundleIdentifiers, id: \.self) { bundleID in
                            Label {
                                Text(bundleID)
                                    .font(.subheadline.monospaced())
                            } icon: {
                                Image(systemName: "app.dashed")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        LabeledContent(language.text("patch.files")) {
                            Text("\(project.rules.count)")
                        }
                        LabeledContent(language.text("patch.folders")) {
                            Text("\(project.directories.count)")
                        }
                        if let workspaceURL = item.workspaceURL {
                            NavigationLink {
                                FileBrowserView(
                                    containerPath: workspaceURL.path,
                                    title: project.name,
                                    bundleID: nil
                                )
                            } label: {
                                Label(
                                    language.text("patch.open_workspace"),
                                    systemImage: "folder"
                                )
                            }
                        }
                    } header: {
                        Text(language.text("patch.workspace"))
                    } footer: {
                        Text(language.text("patch.workspace_detail_footer"))
                    }
                } else {
                    Section {
                        ForEach(project.rules) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                HStack(spacing: 10) {
                                    ruleSummary(rule)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(language.text("patch.edit_rule_hint"))
                        }
                    } header: {
                        Text(language.text("patch.rules"))
                    } footer: {
                        Text(language.text("patch.legacy_footer"))
                    }
                }

                Section(language.text("patch.password")) {
                    HStack(spacing: 12) {
                        Image(systemName: item.summary.isPasswordProtected ? "lock.fill" : "lock.open")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24)
                        Text(language.text(item.summary.isPasswordProtected
                            ? "patch.password_locked"
                            : "patch.no_password"))
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        showApplyConfirmation = true
                    } label: {
                        actionLabel("patch.apply", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(isWorking || receipt != nil)

                    if receipt != nil {
                        Button {
                            showResetConfirmation = true
                        } label: {
                            actionLabel("patch.reset", systemImage: "arrow.counterclockwise.circle")
                        }
                        .disabled(isWorking)

                        Button(role: .destructive) {
                            showRestoreConfirmation = true
                        } label: {
                            actionLabel("patch.restore", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(isWorking)
                    }

                    Button(action: prepareExport) {
                        actionLabel("patch.export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(language.text("patch.apply_footer"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item?.project?.name ?? language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isWorking {
                    ProgressView()
                } else if !isWorkspaceProject, item?.canInspectContents == true {
                    Button(language.text("patch.edit")) { showEditor = true }
                        .disabled(item?.project == nil)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let item, let project = item.project {
                PatchProjectEditorView(
                    existingProject: project,
                    passwordIsProtected: item.summary.isPasswordProtected
                ) { updatedProject, _ in
                    store.update(project: updatedProject)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            PatchRuleEditorView(rule: rule) { updatedRule in
                updateRule(updatedRule)
            }
        }
        .confirmationDialog(
            language.text("patch.apply_confirm_title"),
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.apply")) { apply() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.apply_confirm_message"))
        }
        .confirmationDialog(
            language.text("patch.restore_confirm_title"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.restore"), role: .destructive) { prepareRestore() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.restore_confirm_message"))
        }
        .confirmationDialog(
            language.text("patch.restore_changed_title"),
            isPresented: $showChangedRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.restore_changed_action"), role: .destructive) {
                restore(allowChangedTargets: true)
            }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(changedRestoreMessage)
        }
        .confirmationDialog(
            language.text("patch.reset_confirm_title"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.reset"), role: .destructive) { resetToAppliedState() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.reset_confirm_message"))
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        .sheet(item: $shareRequest) { request in
            PatchActivityView(items: [request.url])
                .ignoresSafeArea()
        }
    }

    private func actionLabel(_ key: String, systemImage: String) -> some View {
        Label(language.text(key), systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func patchInfoRow(
        label: String,
        value: String
    ) -> some View {
        patchInfoRow(label: label) {
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    private func patchInfoRow<Content: View>(
        label: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            value()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
    }

    private func ruleSummary(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(rule.replacementFilename, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 3)
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = item?.project,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func apply() {
        guard let item, let baseProject = item.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2 && item.canInspectContents
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    private func prepareExport() {
        guard let item else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                if item.summary.schemaVersion >= 2, item.canInspectContents {
                    _ = try PatchProjectLibrary.synchronizeWorkspace(item: item)
                }
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    shareRequest = PatchShareRequest(url: item.packageURL)
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.invalid_project"
                    )
                }
            }
        }
    }

    private var changedRestoreMessage: String {
        guard item?.project?.isPrivate != true || item?.isAuthorCopy == true else {
            return language.text(
                "patch.restore_changed_private_message",
                Int64(restoreChangedPaths.count)
            )
        }
        var visiblePaths = restoreChangedPaths.prefix(5).joined(separator: "\n")
        if restoreChangedPaths.count > 5 {
            visiblePaths += "\n…"
        }
        return language.text(
            "patch.restore_changed_message",
            Int64(restoreChangedPaths.count),
            visiblePaths
        )
    }

    private func prepareRestore() {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
                if inspection.changedTargets.isEmpty {
                    try DevicePatchService.restore(receipt: receipt)
                    await MainActor.run {
                        isWorking = false
                        actionAlert = PatchStoreAlert(
                            titleKey: "common.done",
                            messageKey: "patch.restored_message"
                        )
                    }
                } else {
                    await MainActor.run {
                        isWorking = false
                        restoreChangedPaths = inspection.changedTargets.map(\.displayPath)
                        showChangedRestoreConfirmation = true
                    }
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.restore"
                    )
                }
            }
        }
    }

    private func restore(allowChangedTargets: Bool) {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(
                    receipt: receipt,
                    allowChangedTargets: allowChangedTargets
                )
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                }
            }
        }
    }

    private func resetToAppliedState() {
        guard let receipt, let project = item?.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.resetToAppliedState(
                    receipt: receipt,
                    project: project
                )
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.done",
                        messageKey: "patch.reset_message"
                    )
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.reset"
                    )
                }
            }
        }
    }

    private func privateErrorKey(for error: PatchPackageError) -> String {
        guard item?.project?.isPrivate == true,
              item?.isAuthorCopy == false else {
            return error.localizationKey
        }
        return "patch.error.private_operation"
    }

    private func privateErrorArgument(for error: PatchPackageError) -> String? {
        guard item?.project?.isPrivate == true,
              item?.isAuthorCopy == false else {
            return error.localizationArgument
        }
        return nil
    }
}

private struct PatchShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PatchActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}


private struct ExternalPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var remoteControl: RemoteControlService
    @State private var selectedSection = 0
    @State private var aimOn = true
    @State private var headPriority = false
    @State private var fineAim = false
    @State private var quickHeal = false
    @State private var boxESP = true
    @State private var healthESP = true
    @State private var nameESP = true
    @State private var distanceESP = false
    @State private var directionESP = false
    @State private var markEnemies = false
    @State private var effectDistance = 120.0
    @State private var isStarting = false
    @State private var statusMessage: String?

    private let red = Color(red: 0.92, green: 0.08, blue: 0.10)
    private let panel = Color(red: 0.055, green: 0.055, blue: 0.065)
    private let row = Color(red: 0.095, green: 0.095, blue: 0.11)

    private var panelSystemPatch: RemotePatchInfo? {
        remoteControl.patchCatalog.first {
            $0.name.localizedCaseInsensitiveContains("painel system")
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    sidebar
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionContent
                            Spacer(minLength: 12)
                        }
                        .padding(16)
                    }
                }
                footer
            }
            .background(panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            }
            .padding(10)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.title3.weight(.bold))
                .foregroundStyle(red)
            VStack(alignment: .leading, spacing: 2) {
                Text("EXTERNAL")
                    .font(.headline.weight(.bold))
                    .tracking(1.1)
                Text("PAINEL EXTERNO")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.28))
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 8)
            sidebarButton(icon: "scope", title: "MIRA", index: 0)
            sidebarButton(icon: "eye.fill", title: "ESP", index: 1)
            sidebarButton(icon: "gearshape.2.fill", title: "GERAL", index: 2)
            sidebarButton(icon: "figure.stand", title: "RAIO-X", index: 3)
            Spacer()
        }
        .frame(width: 76)
        .background(Color.black.opacity(0.2))
    }

    private func sidebarButton(icon: String, title: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedSection = index
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.4)
            }
            .foregroundStyle(selectedSection == index ? .white : .secondary)
            .frame(width: 58, height: 58)
            .background(selectedSection == index ? red.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .leading) {
                if selectedSection == index {
                    Capsule().fill(red).frame(width: 3, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case 0: aimSection
        case 1: espSection
        case 2: generalSection
        default: xraySection
        }
    }

    private var aimSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("AIMBOT", icon: "scope")
            optionRow("Aimbot ao disparar", icon: "scope", isOn: $aimOn)
            optionRow("Priorizar cabeça", icon: "target", isOn: $headPriority)
            optionRow("Ajuste fino da mira", icon: "slider.horizontal.3", isOn: $fineAim)
            optionRow("Cura rápida", icon: "cross.case.fill", isOn: $quickHeal)
            percentageSelector
        }
    }

    private var espSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("PLAYER ESP", icon: "eye.fill")
            optionRow("Caixa", icon: "square.dashed", isOn: $boxESP)
            optionRow("Vida", icon: "heart.fill", isOn: $healthESP)
            optionRow("Nome", icon: "person.fill", isOn: $nameESP)
            optionRow("Distância", icon: "ruler.fill", isOn: $distanceESP)
            optionRow("Direção", icon: "location.north.fill", isOn: $directionESP)
            optionRow("Marcar inimigos", icon: "mappin.and.ellipse", isOn: $markEnemies)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Distância dos efeitos").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(effectDistance)) m").font(.caption.monospacedDigit()).foregroundStyle(red)
                }
                Slider(value: $effectDistance, in: 20...250, step: 5)
                    .tint(red)
            }
            .padding(12)
            .background(row, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("GERAL", icon: "gearshape.2.fill")
            optionRow("Modo seguro", icon: "checkmark.shield.fill", isOn: .constant(true))
            optionRow("Reduzir efeitos", icon: "sparkles", isOn: .constant(false))
            optionRow("Mostrar status", icon: "info.circle.fill", isOn: .constant(true))
        }
    }

    private var xraySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("RAIO-X", icon: "figure.stand")
            optionRow("Esqueleto", icon: "figure.stand", isOn: .constant(false))
            optionRow("Linhas de direção", icon: "point.3.connected.trianglepath.dotted", isOn: .constant(false))
            optionRow("Alerta de proximidade", icon: "bell.badge.fill", isOn: .constant(false))
        }
    }

    private var percentageSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRECISÃO").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(red)
            HStack(spacing: 7) {
                ForEach(["NORMAL", "90%", "85%", "75%", "65%"], id: \.self) { value in
                    Text(value)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(value == "NORMAL" ? .black : .white)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(value == "NORMAL" ? .white : Color.white.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(12)
        .background(row, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(red)
            Text(title).font(.headline.weight(.bold)).tracking(1.2)
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private func optionRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(red).frame(width: 22)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(ExternalToggleStyle(accent: red))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(row, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 9) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.contains("ativado") ? .green : .secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button {
                    statusMessage = "Configurações limpas"
                } label: {
                    Label("LIMPAR DADOS", systemImage: "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: startPanelSystem) {
                    HStack(spacing: 8) {
                        if isStarting { ProgressView().tint(.white) }
                        else { Image(systemName: "play.fill") }
                        Text(isStarting ? "INICIANDO" : "INICIAR")
                            .font(.subheadline.weight(.bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 44)
                    .background(red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: red.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(ExternalPressStyle())
                .disabled(isStarting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.34))
    }

    private func startPanelSystem() {
        guard let patch = panelSystemPatch else {
            statusMessage = "PAINEL SYSTEM não está disponível no catálogo remoto."
            return
        }
        isStarting = true
        statusMessage = "Preparando PAINEL SYSTEM..."
        withAnimation(.easeInOut(duration: 0.2)) {
            remoteControl.setPatchActive(patch, active: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isStarting = false
            statusMessage = "PAINEL SYSTEM ativado"
        }
    }
}

private struct ExternalToggleStyle: ToggleStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                configuration.isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(configuration.isOn ? accent : Color(uiColor: .systemGray4))
                .frame(width: 45, height: 26)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct ExternalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

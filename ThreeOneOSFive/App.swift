import SwiftUI
import UIKit
import Security
import Foundation

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var licenseManager = LicenseManager()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if licenseManager.isLoading {
                    ActivationLoadingView()
                } else if !licenseManager.isAuthorized {
                    ActivationView(manager: licenseManager) { key in
                        await licenseManager.activate(key: key)
                    }
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                } else {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(patchDraftCoordinator)
                        .environmentObject(fileOperationCoordinator)
                        .environmentObject(patchStore)
                        .environmentObject(repositoryStore)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .opacity(showOnboarding ? 0 : 1)
                        .allowsHitTesting(!showOnboarding)

                    if showOnboarding {
                        OnboardingView {
                            OnboardingStore.markCompleted()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                                showOnboarding = false
                            }
                            appState.detectSupport()
                            checkForUpdate()
                        }
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.98))
                        )
                        .zIndex(1)
                    }
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                licenseManager.refresh()
                if licenseManager.isAuthorized, !showOnboarding {
                    appState.detectSupport()
                    checkForUpdate()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                licenseManager.refresh()
                guard licenseManager.isAuthorized, !showOnboarding else { return }
                appState.detectSupport()
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}


@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var isAuthorized = false
    @Published private(set) var message: String?

    private let endpoint = "https://proxiesystem.org/api/trpc/android.validateKey"
    private let keychainService = "com.apple.mobile.MobileHouseArrest.activation"
    private let keychainAccount = "license-key"
    private var storedKey: String?
    private var refreshInFlight = false

    init() {
        storedKey = Self.loadKey(service: keychainService, account: keychainAccount)
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isLoading = true
        let key = storedKey
        Task {
            guard let key, !key.isEmpty else {
                isAuthorized = false
                message = nil
                isLoading = false
                return
            }
            do {
                let result = try await validate(key: key)
                if result.isValid {
                    isAuthorized = true
                    message = nil
                } else {
                    revoke()
                    message = result.message
                }
            } catch {
                // A transient network failure does not erase a previously valid key.
                // Invalid or expired responses always revoke it above.
                isAuthorized = storedKey != nil
                message = isAuthorized ? nil : "Unable to connect to the activation service."
            }
            isLoading = false
            refreshInFlight = false
        }
    }

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            message = "Enter a license key."
            return
        }
        isLoading = true
        message = nil
        do {
            let result = try await validate(key: key)
            guard result.isValid else {
                isAuthorized = false
                message = result.message ?? "Invalid or expired key."
                isLoading = false
                return
            }
            try Self.saveKey(key, service: keychainService, account: keychainAccount)
            storedKey = key
            isAuthorized = true
            message = nil
        } catch {
            isAuthorized = false
            message = "Unable to validate the key right now."
        }
        isLoading = false
    }

    private func revoke() {
        Self.deleteKey(service: keychainService, account: keychainAccount)
        storedKey = nil
        isAuthorized = false
    }

    private struct ValidationResult {
        let isValid: Bool
        let message: String?
    }

    private func validate(key: String) async throws -> ValidationResult {
        var components = URLComponents(string: endpoint)!
        let payload: [String: Any] = ["json": ["key": key]]
        let inputData = try JSONSerialization.data(withJSONObject: payload)
        components.queryItems = [
            URLQueryItem(name: "input", value: String(data: inputData, encoding: .utf8)!)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let fields = Self.findLicenseFields(in: root)
        let status = (fields["status"] as? String)?.lowercased()
        let valid = fields["valid"] as? Bool ?? fields["success"] as? Bool
        let expirationText = fields["expiresAt"] as? String ?? fields["expirationDate"] as? String
        let expirationDate = expirationText.flatMap { ISO8601DateFormatter().date(from: $0) }
        let expiresIn = (fields["expiresIn"] as? NSNumber)?.doubleValue
        let expiredByDate = expirationDate.map { $0 <= Date() } ?? false
        let expiredByDuration = expiresIn.map { $0 <= 0 } ?? false
        let activeStatus = status == "active" || status == "valid"
        let isValid = (valid ?? activeStatus) && !expiredByDate && !expiredByDuration
        let message = fields["message"] as? String ?? fields["reason"] as? String
        return ValidationResult(isValid: isValid, message: message)
    }

    private static func findLicenseFields(in value: Any) -> [String: Any] {
        if let dictionary = value as? [String: Any] {
            let keys = ["valid", "success", "status", "expiresAt", "expirationDate", "expiresIn", "message", "reason"]
            if keys.contains(where: { dictionary[$0] != nil }) { return dictionary }
            for child in dictionary.values {
                let found = findLicenseFields(in: child)
                if !found.isEmpty { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                let found = findLicenseFields(in: child)
                if !found.isEmpty { return found }
            }
        }
        return [:]
    }

    private static func saveKey(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw URLError(.cannotSaveFile) }
        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw URLError(.cannotSaveFile)
        }
    }

    private static func loadKey(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKey(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

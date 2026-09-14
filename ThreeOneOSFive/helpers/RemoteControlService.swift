import Foundation
import SwiftUI
#if canImport(CryptoKit)
import CryptoKit
#endif

private struct RemoteEnvelope: Decodable {
    struct Result: Decodable {
        struct DataValue: Decodable { let json: RemotePayload }
        let data: DataValue
    }
    let result: Result
}

struct RemotePatchInfo: Decodable, Equatable {
    let id: Int
    let name: String
    let target: String
    let filename: String
    let game: String
    let category: String
    let avatarUrl: String?
    let enabled: Bool
}

private struct RemotePayload: Decodable {
    let config: RemoteConfigPayload
    let patches: [RemotePatchPayload]
}

private struct RemoteConfigPayload: Decodable {
    let accentColor: String
    let secondaryColor: String
    let backgroundColor: String
    let backgroundUrl: String?
    let backgroundVideoUrl: String?
    let revision: Int
}

private struct RemotePatchPayload: Decodable {
    let id: Int
    let name: String
    let target: String
    let filename: String
    let assetUrl: String
    let assetKey: String
    let sha256: String
    let enabled: Bool
    let game: String
    let category: String
    let avatarUrl: String?
    let avatarKey: String?

    var info: RemotePatchInfo {
        RemotePatchInfo(id: id, name: name, target: target, filename: filename, game: game, category: category, avatarUrl: avatarUrl, enabled: enabled)
    }
}

final class RemoteControlService: ObservableObject {
    static let patchesDidChange = Notification.Name("RemoteControlService.patchesDidChange")
    private let baseURL = EndpointVault.remoteBaseURL
    private let queue = DispatchQueue(label: "external.system.remote-control", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isSyncing = false
    private var isAuthorized = false
    private var lastRevision = 0
    private var lastPayloadSignature = ""
    private let managedKey = "external-system.remote-managed-filenames"
    private let disabledKey = "external-system.remote-disabled-filenames"
    private let enabledKey = "external-system.remote-enabled-filenames"

    @Published private(set) var backgroundURL: URL?
    @Published private(set) var backgroundVideoURL: URL?
    @Published private(set) var backgroundColor: Color = AppTheme.pageBackground
    @Published private(set) var patchCatalog: [RemotePatchInfo] = []

    func start() {
        guard isAuthorized else { return }
        syncNow()
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 2)
        timer.setEventHandler { [weak self] in self?.syncNow() }
        timer.resume()
        self.timer = timer
    }

    func refreshNow() {
        guard isAuthorized else { return }
        queue.async { [weak self] in self?.syncNow(force: true) }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
        if authorized {
            start()
            for delay in [0.5, 2.0, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.refreshNow()
                }
            }
        } else {
            stop()
            DispatchQueue.main.async {
                self.backgroundURL = nil
                self.backgroundVideoURL = nil
                self.backgroundColor = AppTheme.pageBackground
                self.patchCatalog = []
            }
        }
    }

    private func syncNow(force: Bool = false) {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        var components = URLComponents(url: baseURL.appendingPathComponent(EndpointVault.remoteConfigPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "sync", value: String(Int(Date().timeIntervalSince1970)))]
        guard let endpoint = components?.url else {
            isSyncing = false
            return
        }
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("EXTERNAL-SYSTEM/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            defer { self.isSyncing = false }
            guard error == nil, let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let errorMessage = error?.localizedDescription ?? "unknown"
                log("remote: config request failed status=\(status) error=\(errorMessage)")
                return
            }
            do {
                let decoder = JSONDecoder()
                if let batch = try? decoder.decode([RemoteEnvelope].self, from: data),
                   let envelope = batch.first {
                    self.apply(envelope.result.data.json, force: force)
                } else {
                    let envelope = try decoder.decode(RemoteEnvelope.self, from: data)
                    self.apply(envelope.result.data.json, force: force)
                }
            } catch {
                log("remote: invalid config response error=\(error.localizedDescription)")
            }
        }.resume()
    }

    private func apply(_ payload: RemotePayload, force: Bool = false) {
        guard isAuthorized else { return }
        let signature = payloadSignature(payload)
        guard force || signature != lastPayloadSignature else { return }
        lastPayloadSignature = signature
        DispatchQueue.main.async {
            self.backgroundURL = payload.config.backgroundUrl.flatMap { URL(string: self.resolvedURL($0)) }
            self.backgroundVideoURL = payload.config.backgroundVideoUrl.flatMap { URL(string: self.resolvedURL($0)) }
            self.backgroundColor = AppTheme.pageBackground
            self.patchCatalog = payload.patches.filter(\.enabled).map(\.info)
        }
        lastRevision = payload.config.revision
        queue.async { self.reconcile(patches: payload.patches) }
    }

    private func payloadSignature(_ payload: RemotePayload) -> String {
        let patches = payload.patches
            .sorted { $0.filename < $1.filename }
            .map { "\($0.filename)|\($0.assetKey)|\($0.sha256)|\($0.enabled)|\($0.game)|\($0.category)" }
            .joined(separator: ";")
        return "\(payload.config.revision)|\(payload.config.backgroundColor)|\(payload.config.backgroundUrl ?? "")|\(patches)"
    }

    private func reconcile(patches: [RemotePatchPayload]) {
        guard isAuthorized else { return }
        guard let root = try? PatchProjectLibrary.packageRootURL() else { return }
        let disabled = Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
        let locallyEnabled = Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [])
        let active = Set(patches.filter { $0.enabled && locallyEnabled.contains($0.filename) }.map(\.filename))
        var managed = Set(UserDefaults.standard.stringArray(forKey: managedKey) ?? [])
        for patch in patches where patch.enabled {
            guard isAuthorized else { return }
            if disabled.contains(patch.filename) || !locallyEnabled.contains(patch.filename) { continue }
            do {
                let url = root.appendingPathComponent(patch.filename)
                let exists = FileManager.default.fileExists(atPath: url.path)
                let matches: Bool
                if exists {
                    matches = try SHA256.hex(of: PatchProjectLibrary.readPackage(at: url)) == patch.sha256.lowercased()
                } else {
                    matches = false
                }
                if !matches {
                    try downloadAndInstall(patch, existingURL: exists ? url : nil, destinationURL: url)
                }
                managed.insert(patch.filename)
            } catch {
                log("remote: skipped patch")
            }
        }
        for item in PatchProjectLibrary.load() where managed.contains(item.packageURL.lastPathComponent) && !active.contains(item.packageURL.lastPathComponent) {
            let filename = item.packageURL.lastPathComponent
            let url = root.appendingPathComponent(filename)
            try? PatchProjectLibrary.delete(item)
            try? FileManager.default.removeItem(at: url)
            managed.remove(filename)
        }
        UserDefaults.standard.set(Array(managed), forKey: managedKey)
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.patchesDidChange, object: nil) }
    }

    func isPatchActive(_ patch: RemotePatchInfo) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? []).contains(patch.filename)
    }

    func setPatchActive(_ patch: RemotePatchInfo, active: Bool) {
        var disabled = Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
        var enabled = Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [])
        let root = try? PatchProjectLibrary.packageRootURL()
        let url = root?.appendingPathComponent(patch.filename)
        if active {
            disabled.remove(patch.filename)
            enabled.insert(patch.filename)
            refreshNow()
        } else {
            disabled.insert(patch.filename)
            enabled.remove(patch.filename)
            if let item = PatchProjectLibrary.load().first(where: { $0.packageURL.lastPathComponent == patch.filename }) {
                if let project = item.project, let receipt = DevicePatchService.latestReceipt(projectID: project.id) {
                    try? DevicePatchService.restore(receipt: receipt)
                }
                try? PatchProjectLibrary.delete(item)
            }
            if let url { try? FileManager.default.removeItem(at: url) }
        }
        UserDefaults.standard.set(Array(disabled), forKey: disabledKey)
        UserDefaults.standard.set(Array(enabled), forKey: enabledKey)
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.patchesDidChange, object: nil) }
    }

    private func downloadAndInstall(_ patch: RemotePatchPayload, existingURL: URL?, destinationURL: URL) throws {
        let url = URL(string: resolvedURL(patch.assetUrl))!
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(URLError(.unknown))
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error { result = .failure(error) }
            else if let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) { result = .success(data) }
            else { result = .failure(URLError(.badServerResponse)) }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        let data = try result.get()
        guard try SHA256.hex(of: data) == patch.sha256.lowercased() else { throw PatchPackageError.invalidProject }
        let summary = try PatchPackageCodec.inspect(data)
        guard !summary.isPasswordProtected else { throw PatchPackageError.invalidProject }
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        _ = try PatchProjectLibrary.save(
            data: data,
            projectName: patch.filename,
            existingURL: existingURL ?? destinationURL
        )
        if summary.schemaVersion >= 2 {
            _ = try PatchWorkspaceService.replaceWorkspace(with: decoded.project)
        } else {
            try? PatchWorkspaceService.deleteWorkspace(projectID: decoded.project.id)
        }
        do {
            _ = try DevicePatchService.apply(project: decoded.project)
        } catch {
            log("remote: patch downloaded but could not apply yet")
        }
    }

    private func resolvedURL(_ value: String) -> String {
        if value.hasPrefix("/") { return baseURL.appendingPathComponent(value).absoluteString }
        return value
    }
}

private enum SHA256 {
    static func hex(of data: Data) throws -> String {
        #if canImport(CryptoKit)
        return CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        throw PatchPackageError.invalidProject
        #endif
    }
}

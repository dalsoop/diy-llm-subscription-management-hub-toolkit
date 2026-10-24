import CodexBarCore
import Foundation
import Observation

public enum OpenCodexAccessRenameCapability: Equatable, Sendable {
    case unchecked, available, unsupported

    public var localizationKey: String? {
        switch self {
        case .unchecked: "opencodex_access_rename_unchecked"
        case .available: nil
        case .unsupported: OpenCodexAccessError.renameUnsupported.accessLocalizationKey
        }
    }
}

public enum OpenCodexAccessOperation: Equatable, Sendable {
    case create, rename, revoke
}

public enum OpenCodexAccessMutationOutcome: Equatable, Sendable {
    case succeeded(OpenCodexAccessOperation)
    case failed(OpenCodexAccessError)
}

/// Owned by the app root, not a settings pane. No timers, persistence, raw errors, or secret strings.
@MainActor
@Observable
public final class OpenCodexAccessStore {
    public private(set) var snapshot: OpenCodexAccessKeyList?
    public private(set) var status: OpenCodexAccessStatus?
    public private(set) var isRefreshing = false
    public private(set) var isMutating = false
    public private(set) var isActive = false
    public private(set) var refreshError: OpenCodexAccessError?
    public private(set) var inputError: OpenCodexAccessError?
    public private(set) var mutationOutcome: OpenCodexAccessMutationOutcome?
    public private(set) var disclosure: OpenCodexAccessDisclosure?
    public private(set) var revokeConfirmation: OpenCodexAccessKey?
    public private(set) var renameCapability: OpenCodexAccessRenameCapability
    @ObservationIgnored private var source: any OpenCodexAccessSource
    @ObservationIgnored private var readGeneration: UInt64 = 0
    @ObservationIgnored private var snapshotIsCurrent = false
    @ObservationIgnored private var mutationTask: Task<Void, Never>?

    public init(
        source: any OpenCodexAccessSource,
        renameCapability: OpenCodexAccessRenameCapability = .unchecked)
    {
        self.source = source
        self.renameCapability = renameCapability
    }

    public var canMutate: Bool {
        self.snapshotIsCurrent && !self.isRefreshing && !self.isMutating && self.disclosure == nil
    }

    public var canRename: Bool {
        self.canMutate && self.renameCapability == .available
    }

    /// T4 probes installation metadata without executing management. This never changes the source or a pending result.
    public func updateRenameCapability(_ capability: OpenCodexAccessRenameCapability) {
        self.renameCapability = capability
    }

    /// Commit a path edit only when this returns true. Then call enter/refresh if the pane is visible.
    /// A rejected edit must not be persisted by the caller. Outstanding reads cannot publish across this boundary.
    @discardableResult
    public func reconfigure(
        source: any OpenCodexAccessSource,
        renameCapability: OpenCodexAccessRenameCapability = .unchecked) -> Bool
    {
        guard !self.isMutating, self.disclosure == nil else { return false }
        self.readGeneration &+= 1
        self.source = source
        self.renameCapability = renameCapability
        self.snapshot = nil
        self.status = nil
        self.snapshotIsCurrent = false
        self.isRefreshing = false
        self.refreshError = nil
        self.inputError = nil
        self.mutationOutcome = nil
        self.revokeConfirmation = nil
        return true
    }

    public func enter() async {
        self.isActive = true
        await self.refresh()
    }

    public func leave() {
        self.isActive = false
        self.revokeConfirmation = nil
        // A launched mutation and its follow-up read belong to this store, not to the disappearing view.
        if !self.isMutating {
            self.readGeneration &+= 1
            self.isRefreshing = false
        }
    }

    /// T4 wires activation after returning from the dashboard. Inactive panes never poll.
    public func activate() async {
        guard self.isActive else { return }
        await self.refresh()
    }

    public func refresh() async {
        self.readGeneration &+= 1
        let generation = self.readGeneration
        let source = self.source
        self.isRefreshing = true
        self.snapshotIsCurrent = false
        self.revokeConfirmation = nil
        do {
            let status = try await source.status()
            guard generation == self.readGeneration else { return }
            self.status = status
            try status.requireLocalManagement()
            let snapshot = try await source.list()
            guard generation == self.readGeneration else { return }
            self.snapshot = snapshot
            self.refreshError = nil
            self.snapshotIsCurrent = true
        } catch {
            guard generation == self.readGeneration else { return }
            self.refreshError = Self.safeError(error)
        }
        guard generation == self.readGeneration else { return }
        self.isRefreshing = false
    }

    @discardableResult
    public func create(name: String) -> Bool {
        guard self.canMutate, let name = self.validatedName(name) else { return false }
        return self.start(.create, id: nil, name: name)
    }

    @discardableResult
    public func rename(id: String, name: String) -> Bool {
        guard self.canRename, self.snapshot?.keys.contains(where: { $0.id == id }) == true,
              let name = self.validatedName(name) else { return false }
        return self.start(.rename, id: id, name: name)
    }

    @discardableResult
    public func requestRevoke(id: String) -> Bool {
        guard self.canMutate, let key = self.snapshot?.keys.first(where: { $0.id == id }) else { return false }
        self.revokeConfirmation = key
        return true
    }

    public func cancelRevoke() { self.revokeConfirmation = nil }

    @discardableResult
    public func confirmRevoke() -> Bool {
        guard self.canMutate, let key = self.revokeConfirmation,
              self.snapshot?.keys.contains(key) == true else { return false }
        return self.start(.revoke, id: key.id, name: nil)
    }

    public func dismissDisclosure() { self.disclosure = nil }

    /// Useful for injected harnesses; leaving a pane must never cancel this task.
    public func waitForMutation() async { await self.mutationTask?.value }

    private func validatedName(_ raw: String) -> String? {
        do {
            let name = try OpenCodexAccessName.validate(raw)
            self.inputError = nil
            return name
        } catch {
            self.inputError = .invalidName
            return nil
        }
    }

    private func start(_ operation: OpenCodexAccessOperation, id: String?, name: String?) -> Bool {
        self.isMutating = true
        self.snapshotIsCurrent = false
        self.readGeneration &+= 1
        self.isRefreshing = false
        self.inputError = nil
        self.mutationOutcome = nil
        self.revokeConfirmation = nil
        let source = self.source
        self.mutationTask = Task {
            do {
                switch operation {
                case .create:
                    // Do not keep the creation response in an async stack across the follow-up read.
                    self.disclosure = try await OpenCodexAccessDisclosure(result: source.create(name: name ?? ""))
                case .rename:
                    _ = try await source.rename(id: id ?? "", name: name ?? "")
                case .revoke:
                    try await source.revoke(id: id ?? "")
                }
                self.mutationOutcome = .succeeded(operation)
            } catch {
                let error = (error as? OpenCodexAccessError) ?? .confirmationRequired
                self.mutationOutcome = .failed(error)
                if error == .renameUnsupported {
                    self.renameCapability = .unsupported
                    // No mutation was sent; preserve the current rows and disable rename only.
                    self.snapshotIsCurrent = self.snapshot != nil && self.refreshError == nil && !self.isRefreshing
                    self.isMutating = false
                    self.mutationTask = nil
                    return
                }
            }
            await self.refresh()
            self.isMutating = false
            self.mutationTask = nil
        }
        return true
    }

    private static func safeError(_ error: any Error) -> OpenCodexAccessError {
        (error as? OpenCodexAccessError) ?? .communicationFailed
    }
}

public enum OpenCodexAccessUsagePresentation: Equatable {
    case unavailable, noRecordedUsage
    case recorded(requests7d: Double?, totalRequests: Double?, lastUsedAt: Date?)

    public init(key: OpenCodexAccessKey, list: OpenCodexAccessKeyList) {
        guard let since = list.attributionSince, since.timeIntervalSince1970.isFinite,
              case let .recorded(week, total, last) = key.usage,
              [week, total].allSatisfy({ value in
                  guard let value else { return true }
                  return value.isFinite && value >= 0
              })
        else { self = .unavailable; return }
        if key.usage.hasNoRecordedUsage {
            self = .noRecordedUsage
        } else if week == nil, total == nil, last == nil {
            self = .unavailable
        } else {
            self = .recorded(requests7d: week, totalRequests: total, lastUsedAt: last)
        }
    }
}

extension OpenCodexAccessError {
    /// Typed, fixed UI keys only. Never use localizedDescription or process output in this pane.
    public var accessLocalizationKey: String {
        "opencodex_access_error_\(self.rawValue)"
    }
}

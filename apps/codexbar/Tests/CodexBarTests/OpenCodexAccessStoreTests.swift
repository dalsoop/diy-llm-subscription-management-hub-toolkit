import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

actor OpenCodexAccessFakeSource: OpenCodexAccessSource {
    var role: OpenCodexRuntimeRole = .hub
    var snapshot = OpenCodexAccessKeyList(keys: [])
    var listError: OpenCodexAccessError?
    var mutationError: OpenCodexAccessError?
    var calls: [String] = []
    var suspendedCreate: CheckedContinuation<OpenCodexAccessCreatedKey, any Error>?
    var delayCreate = false
    var delayLists = false
    var lists: [CheckedContinuation<OpenCodexAccessKeyList, any Error>] = []

    func configure(
        role: OpenCodexRuntimeRole = .hub,
        snapshot: OpenCodexAccessKeyList = .init(keys: []),
        listError: OpenCodexAccessError? = nil,
        mutationError: OpenCodexAccessError? = nil,
        delayCreate: Bool = false,
        delayLists: Bool = false)
    {
        self.role = role
        self.snapshot = snapshot
        self.listError = listError
        self.mutationError = mutationError
        self.delayCreate = delayCreate
        self.delayLists = delayLists
    }

    func status() async throws -> OpenCodexAccessStatus {
        self.calls.append("status")
        return .init(runtimeRole: self.role, proxyRunning: true, dashboardURL: nil)
    }

    func list() async throws -> OpenCodexAccessKeyList {
        self.calls.append("list")
        if self.delayLists {
            return try await withCheckedThrowingContinuation { self.lists.append($0) }
        }
        if let listError { throw listError }
        return self.snapshot
    }

    func create(name: String) async throws -> OpenCodexAccessCreatedKey {
        self.calls.append("create:\(name)")
        if let mutationError { throw mutationError }
        if self.delayCreate {
            return try await withCheckedThrowingContinuation { self.suspendedCreate = $0 }
        }
        return Self.created(name: name)
    }

    static func created(name: String) -> OpenCodexAccessCreatedKey {
        .init(id: "full-created-id", name: name, createdAt: .distantPast, secret: .init("synthetic-secret"))
    }

    func finishCreate() {
        self.suspendedCreate?.resume(returning: Self.created(name: "new"))
        self.suspendedCreate = nil
    }

    func finishList(_ index: Int, with snapshot: OpenCodexAccessKeyList) {
        self.lists[index].resume(returning: snapshot)
    }

    func rename(id: String, name: String) async throws -> OpenCodexAccessRenamedKey {
        self.calls.append("rename:\(id):\(name)")
        if let mutationError { throw mutationError }
        return .init(id: id, name: name, createdAt: .distantPast)
    }

    func revoke(id: String) async throws {
        self.calls.append("revoke:\(id)")
        if let mutationError { throw mutationError }
    }
}

@MainActor
struct OpenCodexAccessStoreTests {
    static func key(_ id: String, usage: OpenCodexAccessUsage = .unavailable) -> OpenCodexAccessKey {
        .init(
            id: id,
            name: "same name",
            prefix: "masked…",
            createdAt: .distantPast,
            allowedProviders: ["synthetic-provider"],
            allowedModels: ["synthetic-model"],
            usage: usage)
    }

    @Test
    func `failed refresh retains stale rows and forbids all mutations`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(snapshot: .init(keys: [Self.key("full-id")]))
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        #expect(store.canMutate)
        await source.configure(listError: .communicationFailed)
        await store.refresh()
        #expect(store.snapshot?.keys.count == 1)
        #expect(store.refreshError == .communicationFailed)
        #expect(!store.create(name: "new"))
        #expect(!store.rename(id: "full-id", name: "new"))
        #expect(!store.requestRevoke(id: "full-id"))
    }

    @Test
    func `creation survives leaving and rejects duplicate clicks and reconfiguration until disclosure closes`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(delayCreate: true)
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        #expect(store.create(name: " new "))
        #expect(!store.create(name: "duplicate"))
        #expect(!store.reconfigure(source: OpenCodexAccessFakeSource()))
        store.leave()
        while await source.suspendedCreate == nil {
            await Task.yield()
        }
        await source.finishCreate()
        await store.waitForMutation()
        #expect(store.disclosure?.name == "new")
        #expect(store.mutationOutcome == .succeeded(.create))
        #expect(!store.reconfigure(source: OpenCodexAccessFakeSource()))
        weak var secret = store.disclosure?.secret
        #expect(secret != nil)
        store.dismissDisclosure()
        #expect(secret == nil)
        #expect(store.reconfigure(source: OpenCodexAccessFakeSource()))
        #expect(await source.calls.filter { $0.hasPrefix("create:") } == ["create:new"])
    }

    @Test
    func `mutation success is independent of refresh failure`() async {
        let source = OpenCodexAccessFakeSource()
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        await source.configure(listError: .communicationFailed)
        #expect(store.create(name: "new"))
        await store.waitForMutation()
        #expect(store.mutationOutcome == .succeeded(.create))
        #expect(store.refreshError == .communicationFailed)
        #expect(store.disclosure != nil)
    }

    @Test
    func `same name rows use full IDs and revoke requires current confirmation`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(snapshot: .init(keys: [Self.key("full-a"), Self.key("full-b")]))
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        #expect(!store.confirmRevoke())
        #expect(store.requestRevoke(id: "full-b"))
        store.cancelRevoke()
        #expect(!store.confirmRevoke())
        #expect(store.rename(id: "full-a", name: "renamed"))
        await store.waitForMutation()
        #expect(store.requestRevoke(id: "full-b"))
        #expect(store.revokeConfirmation?.prefix == "masked…")
        #expect(store.confirmRevoke())
        await store.waitForMutation()
        let calls = await source.calls
        #expect(calls.contains("rename:full-a:renamed"))
        #expect(calls.filter { $0.hasPrefix("revoke:") } == ["revoke:full-b"])
    }

    @Test(arguments: [OpenCodexAccessError.notFound, .permissionDenied, .confirmationRequired])
    func `failed mutation refreshes without retry or success`(_ error: OpenCodexAccessError) async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(snapshot: .init(keys: [Self.key("full-id")]))
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        await source.configure(mutationError: error)
        #expect(store.rename(id: "full-id", name: "new"))
        await store.waitForMutation()
        #expect(store.mutationOutcome == .failed(error))
        #expect(await source.calls.filter { $0.hasPrefix("rename:") }.count == 1)
        #expect(await source.calls.filter { $0 == "list" }.count == 2)
        #expect(store.disclosure == nil)
    }

    @Test
    func `newest refresh wins and leaving prevents activation polling`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(delayLists: true)
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        let first = Task { await store.enter() }
        while await source.lists.count < 1 {
            await Task.yield()
        }
        let second = Task { await store.refresh() }
        while await source.lists.count < 2 {
            await Task.yield()
        }
        await source.finishList(1, with: .init(keys: [Self.key("new")]))
        await second.value
        await source.finishList(0, with: .init(keys: [Self.key("old")]))
        await first.value
        #expect(store.snapshot?.keys.first?.id == "new")
        store.leave()
        await store.activate()
        #expect(await source.lists.count == 2)
    }

    @Test(arguments: [OpenCodexRuntimeRole.client, .unknown])
    func `nonlocal role never queries keys or mutates`(_ role: OpenCodexRuntimeRole) async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(role: role)
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        #expect(store.refreshError == .unsupportedRole)
        #expect(!store.create(name: "new"))
        #expect(await source.calls == ["status"])
    }

    @Test
    func `invalid names and missing IDs never reach source`() async {
        let source = OpenCodexAccessFakeSource()
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        for name in ["", "a\nb", "--json", String(repeating: "😀", count: 33)] {
            #expect(!store.create(name: name))
            #expect(store.inputError == .invalidName)
        }
        #expect(!store.rename(id: "missing", name: "valid"))
        #expect(!store.requestRevoke(id: "missing"))
        #expect(await source.calls == ["status", "list"])
    }

    @Test
    func `closing disclosure releases secret even while followup read is suspended`() async {
        let source = OpenCodexAccessFakeSource()
        let store = OpenCodexAccessStore(source: source)
        await store.enter()
        await source.configure(delayLists: true)
        #expect(store.create(name: "new"))
        while await source.lists.isEmpty {
            await Task.yield()
        }
        weak var secret = store.disclosure?.secret
        #expect(secret != nil)
        store.leave()
        #expect(store.disclosure != nil)
        store.dismissDisclosure()
        #expect(secret == nil)
        await source.finishList(0, with: .init(keys: []))
        await store.waitForMutation()
        #expect(store.mutationOutcome == .succeeded(.create))
    }

    @Test
    func `old reads started during creation cannot replace the postmutation refresh`() async {
        let source = OpenCodexAccessFakeSource()
        let store = OpenCodexAccessStore(source: source)
        await store.enter()
        await source.configure(delayCreate: true, delayLists: true)
        #expect(store.create(name: "new"))
        while await source.suspendedCreate == nil {
            await Task.yield()
        }
        let read = Task { await store.refresh() }
        while await source.lists.isEmpty {
            await Task.yield()
        }
        #expect(!store.create(name: "duplicate"))
        await source.finishCreate()
        while await source.lists.count < 2 {
            await Task.yield()
        }
        await source.finishList(1, with: .init(keys: [Self.key("post-mutation")]))
        await store.waitForMutation()
        await source.finishList(0, with: .init(keys: [Self.key("stale")]))
        await read.value
        #expect(store.snapshot?.keys.first?.id == "post-mutation")
    }

    @Test
    func `activation rereads only the visible pane and leave cancels unconfirmed revoke`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(snapshot: .init(keys: [Self.key("full-id")]))
        let store = OpenCodexAccessStore(source: source)
        await store.enter()
        await store.activate()
        #expect(await source.calls.filter { $0 == "list" }.count == 2)
        #expect(store.requestRevoke(id: "full-id"))
        store.leave()
        #expect(!store.confirmRevoke())
        await store.activate()
        #expect(await source.calls.filter { $0 == "list" }.count == 2)
        await store.enter()
        #expect(await source.calls.filter { $0 == "list" }.count == 3)
        #expect(await source.calls.allSatisfy { !$0.hasPrefix("revoke:") })
    }

    @Test
    func `rename capability disables only rename and runtime unsupported preserves populated list`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(snapshot: .init(keys: [Self.key("full-id")]))
        let store = OpenCodexAccessStore(source: source)
        await store.enter()
        #expect(!store.canRename)
        #expect(store.canMutate)
        store.updateRenameCapability(.unsupported)
        #expect(!store.rename(id: "full-id", name: "new"))
        #expect(store.renameCapability.localizationKey == OpenCodexAccessError.renameUnsupported.accessLocalizationKey)
        store.updateRenameCapability(.available)
        await source.configure(mutationError: .renameUnsupported)
        #expect(store.rename(id: "full-id", name: "new"))
        await store.waitForMutation()
        #expect(store.mutationOutcome == .failed(.renameUnsupported))
        #expect(store.snapshot?.keys.first?.id == "full-id")
        #expect(!store.canRename)
        #expect(store.canMutate)
        #expect(store.requestRevoke(id: "full-id"))
        #expect(await source.calls.filter { $0 == "list" }.count == 1)
    }

    @Test
    func `reconfiguration discards outstanding responses and capability is reset`() async {
        let old = OpenCodexAccessFakeSource()
        await old.configure(delayLists: true)
        let store = OpenCodexAccessStore(source: old, renameCapability: .available)
        let read = Task { await store.enter() }
        while await old.lists.isEmpty {
            await Task.yield()
        }
        let replacement = OpenCodexAccessFakeSource()
        #expect(store.reconfigure(source: replacement))
        #expect(store.renameCapability == .unchecked)
        await store.refresh()
        await old.finishList(0, with: .init(keys: [Self.key("old-source")]))
        await read.value
        #expect(store.snapshot?.keys.isEmpty == true)
        #expect(store.canMutate)
    }

    @Test
    func `refresh invalidates revoke confirmation and stale rows cannot be reselected while loading`() async {
        let source = OpenCodexAccessFakeSource()
        await source.configure(snapshot: .init(keys: [Self.key("full-id")]))
        let store = OpenCodexAccessStore(source: source, renameCapability: .available)
        await store.enter()
        #expect(store.requestRevoke(id: "full-id"))
        await source.configure(delayLists: true)
        let read = Task { await store.refresh() }
        while await source.lists.isEmpty {
            await Task.yield()
        }
        #expect(store.revokeConfirmation == nil)
        #expect(!store.confirmRevoke())
        #expect(!store.requestRevoke(id: "full-id"))
        #expect(!store.rename(id: "full-id", name: "new"))
        await source.finishList(0, with: .init(keys: []))
        await read.value
        #expect(store.snapshot?.keys.isEmpty == true)
        #expect(store.refreshError == nil)
    }

    @Test
    func `disclosure debug and reflection redact secret without calling reveal`() {
        let result = OpenCodexAccessFakeSource.created(name: "new")
        let disclosure = OpenCodexAccessDisclosure(result: result)
        #expect(!String(reflecting: disclosure).contains("synthetic-secret"))
        #expect(!String(describing: disclosure).contains("synthetic-secret"))
        #expect(Mirror(reflecting: disclosure).children.isEmpty)
    }

    @Test
    func `usage requires attribution and preserves unknown zero and incomplete distinctions`() {
        let key = Self.key("id", usage: .recorded(requests7d: nil, totalRequests: 0, lastUsedAt: nil))
        #expect(OpenCodexAccessUsagePresentation(key: key, list: .init(keys: [key])) == .unavailable)
        let list = OpenCodexAccessKeyList(keys: [key], attributionSince: .distantPast, usageIncomplete: true)
        #expect(OpenCodexAccessUsagePresentation(key: key, list: list) == .noRecordedUsage)
        let unknown = Self.key("id", usage: .recorded(requests7d: nil, totalRequests: nil, lastUsedAt: nil))
        #expect(OpenCodexAccessUsagePresentation(key: unknown, list: list) == .unavailable)
        let ambiguous = Self.key("id", usage: .ambiguous)
        #expect(OpenCodexAccessUsagePresentation(key: ambiguous, list: list) == .unavailable)
        let partial = Self.key("id", usage: .recorded(requests7d: 3, totalRequests: nil, lastUsedAt: nil))
        #expect(OpenCodexAccessUsagePresentation(key: partial, list: list) == .recorded(
            requests7d: 3, totalRequests: nil, lastUsedAt: nil))
    }
}

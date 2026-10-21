import Foundation

/// The Claude account adapter's view of the opencodex hub's Anthropic pool.
///
/// The source follows the role opencodex reports for this Mac (see `OpenCodexHubReader`). On the hub it runs
/// `ocx account list anthropic --quota --json` and, for an explicit switch, `ocx account use anthropic <id> --json`
/// (fixed argument arrays, never a shell). A Mac linked to a hub reads the hub's snapshot file and asks for a
/// switch with a request file next to it; it never runs `ocx account use`. opencodex keeps the credentials on
/// the hub; CodexBar never reads or stores them, and full account ids stay in memory.
public enum OpenCodexAccountReader {
    public static func readAccountList(
        executablePath: String,
        snapshotPath: String?,
        roleCache: OpenCodexRuntimeRoleCache = .shared,
        now: Date = Date(),
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> ClaudeSwapAccountList
    {
        let read = try await self.mappingErrors {
            try await OpenCodexHubReader.read(
                provider: .anthropic,
                executablePath: executablePath,
                snapshotPath: snapshotPath,
                roleCache: roleCache,
                now: now,
                timeout: timeout)
        }
        return OpenCodexAccountListParser.result(from: read).list
    }

    /// Reads the live hub list. Throws `.hubAccountsUnavailable` when opencodex answers without a list.
    public static func readLiveList(
        executablePath: String,
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> OpenCodexAccountListResult
    {
        let binary = try ClaudeSwapAccountReader.resolvedExecutablePath(executablePath)
        let live = try await self.mappingErrors {
            try await OpenCodexHubReader.readLivePool(provider: .anthropic, binary: binary, timeout: timeout)
        }
        return OpenCodexAccountListParser.result(fromLive: live)
    }

    public static func readSnapshot(path: String) throws -> OpenCodexAccountListResult {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > ClaudeSwapAccountReader.maxOutputBytes {
                throw OpenCodexAccountListError.snapshotUnreadable("file is larger than the list limit")
            }
            data = try Data(contentsOf: url)
        } catch let error as OpenCodexAccountListError {
            throw error
        } catch {
            throw OpenCodexAccountListError.snapshotUnreadable("no readable file at \(url.lastPathComponent)")
        }
        return try OpenCodexAccountListParser.parseSnapshot(data)
    }

    /// Switches the hub's Anthropic pool to the account in `accountNumber`.
    ///
    /// On the hub the live list is read again so the slot is resolved against what the hub lists now;
    /// when `expectedEmail` is given the slot must still hold that (masked) account. Once launched,
    /// `ocx account use` runs to its natural exit. On another Mac the current snapshot is read again with the
    /// same checks and a switch request is written for the hub (`reason == "requested"`).
    public static func switchAccount(
        executablePath: String,
        accountNumber: Int,
        expectedEmail: String?,
        snapshotPath: String? = nil,
        roleCache: OpenCodexRuntimeRoleCache = .shared,
        now: Date = Date(),
        timeout: TimeInterval = ClaudeSwapAccountReader.defaultTimeout) async throws -> ClaudeSwapAccountSwitchResult
    {
        guard accountNumber > 0 else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        let route = try await self.mappingErrors(slot: accountNumber) {
            try await OpenCodexHubReader.switchRoute(
                provider: .anthropic,
                executablePath: executablePath,
                snapshotPath: snapshotPath,
                roleCache: roleCache,
                now: now,
                timeout: timeout)
        }
        let requestsDirectory: URL
        let snapshot: OpenCodexAccountListResult
        switch route {
        case let .hub(live, binary):
            return try await self.switchOnHub(
                OpenCodexAccountListParser.result(fromLive: live),
                accountNumber: accountNumber,
                expectedEmail: expectedEmail,
                binary: binary)
        case let .request(pool, directory):
            snapshot = OpenCodexAccountListParser.result(fromSnapshot: pool)
            requestsDirectory = directory
        }
        let (row, account) = try self.resolve(snapshot, accountNumber: accountNumber, expectedEmail: expectedEmail)
        let previous = snapshot.list.activeAccountNumber
        if row.isActive {
            return ClaudeSwapAccountSwitchResult(
                switched: false, fromAccountNumber: previous, toAccountNumber: accountNumber, reason: "already-active")
        }
        guard let idSuffix = account.idSuffix else {
            throw OpenCodexAccountListError.switchNotAllowed(nil)
        }
        let outcome: OpenCodexHubSwitchOutcome
        do {
            outcome = try OpenCodexHubReader.requestSwitch(
                pool: snapshot.pool,
                idSuffix: idSuffix,
                email: account.email,
                requestsDirectory: requestsDirectory,
                now: now)
        } catch let error as OpenCodexHubReaderError {
            throw OpenCodexAccountListError(error, slot: accountNumber)
        }
        guard case let .requested(request) = outcome else {
            return ClaudeSwapAccountSwitchResult(
                switched: false, fromAccountNumber: previous, toAccountNumber: accountNumber, reason: "already-active")
        }
        return ClaudeSwapAccountSwitchResult(
            switched: false,
            fromAccountNumber: previous,
            toAccountNumber: accountNumber,
            reason: "requested",
            hubRequest: request)
    }

    // MARK: - Private

    /// Runs a hub read and reports its failures in the Claude adapter's error type.
    private static func mappingErrors<T>(slot: Int = 0, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as OpenCodexHubReaderError {
            throw OpenCodexAccountListError(error, slot: slot)
        } catch let error as OpenCodexHubPoolError {
            throw OpenCodexAccountListError(error)
        }
    }

    private static func resolve(
        _ current: OpenCodexAccountListResult,
        accountNumber: Int,
        expectedEmail: String?) throws -> (ClaudeSwapAccountRow, OpenCodexHubAccount)
    {
        guard let row = current.list.accounts.first(where: { $0.number == accountNumber }),
              current.pool.accounts.indices.contains(accountNumber - 1)
        else {
            throw OpenCodexAccountListError.accountNotFound(slot: accountNumber)
        }
        if let expectedEmail = SettingsValue.cleaned(expectedEmail), expectedEmail != row.email {
            throw OpenCodexAccountListError.accountChanged(slot: accountNumber)
        }
        return (row, current.pool.accounts[accountNumber - 1])
    }

    private static func switchOnHub(
        _ current: OpenCodexAccountListResult,
        accountNumber: Int,
        expectedEmail: String?,
        binary: String) async throws -> ClaudeSwapAccountSwitchResult
    {
        let (row, _) = try self.resolve(current, accountNumber: accountNumber, expectedEmail: expectedEmail)
        let previous = current.list.activeAccountNumber
        if row.isActive {
            return ClaudeSwapAccountSwitchResult(
                switched: false,
                fromAccountNumber: previous,
                toAccountNumber: accountNumber,
                reason: "already-active")
        }
        // The slot is listed, but its id cannot be passed to `ocx account use`.
        guard let accountID = current.accountIDs[accountNumber] else {
            throw OpenCodexAccountListError.switchNotAllowed(nil)
        }
        let result = try await SubprocessRunner.runToCompletion(
            binary: binary,
            arguments: ["account", "use", OpenCodexAccountListParser.provider, accountID, "--json"],
            environment: self.environment(for: binary),
            acceptsNonZeroExit: true,
            label: "opencodex switch")
        let activeID: String
        do {
            activeID = try OpenCodexAccountListParser
                .parseSwitchReceipt(OpenCodexHubReader.boundedOutput(result.stdout))
        } catch {
            throw OpenCodexAccountListError.switchFailed(OpenCodexHubReader.diagnostic(result))
        }
        guard activeID == accountID else {
            throw OpenCodexAccountListError.mismatchedTarget
        }
        return ClaudeSwapAccountSwitchResult(
            switched: true,
            fromAccountNumber: previous,
            toAccountNumber: accountNumber,
            reason: "switched")
    }

    static func environment(
        for binary: String,
        base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]
    {
        OpenCodexHubReader.environment(for: binary, base: base)
    }
}

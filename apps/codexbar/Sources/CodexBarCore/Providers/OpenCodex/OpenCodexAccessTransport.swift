import Foundation

/// Process seam for synthetic tests. Raw bytes stay inside the source boundary, never in UI models.
public struct OpenCodexAccessRequest: Sendable {
    public let binary: String
    public let arguments: [String]
    public let input: Data?
    public let mutation: Bool
    public let timeout: TimeInterval
    public let maxOutputBytes: Int

    public init(
        binary: String,
        arguments: [String],
        input: Data? = nil,
        mutation: Bool,
        timeout: TimeInterval = 30,
        maxOutputBytes: Int = 262_144)
    {
        self.binary = binary
        self.arguments = arguments
        self.input = input
        self.mutation = mutation
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }
}

public protocol OpenCodexAccessTransport: Sendable {
    func run(_ request: OpenCodexAccessRequest) async throws -> Data
}

public struct OpenCodexAccessProcessTransport: OpenCodexAccessTransport {
    public init() {}

    public func run(_ request: OpenCodexAccessRequest) async throws -> Data {
        do {
            let pipe = request.input.map { _ in Pipe() }
            if let input = request.input, let pipe {
                // Only the bounded {id,name} helper payload is accepted; never block filling a pipe.
                guard input.count <= 4096 else { throw OpenCodexAccessError.invalidResponse }
                try pipe.fileHandleForWriting.write(contentsOf: input)
                try pipe.fileHandleForWriting.close()
            }
            var environment = OpenCodexHubReader.environment(for: request.binary)
            if request.input != nil {
                // Prevent runtime preload hooks from running before the restricted helper can silence output.
                environment.removeValue(forKey: "NODE_OPTIONS")
                environment.removeValue(forKey: "BUN_OPTIONS")
            }
            let result: SubprocessResult = if request.mutation {
                try await SubprocessRunner.runToCompletion(
                    binary: request.binary,
                    arguments: request.arguments,
                    environment: environment,
                    maxOutputBytes: request.maxOutputBytes,
                    standardInput: pipe,
                    label: "opencodex access mutation")
            } else {
                try await SubprocessRunner.run(
                    binary: request.binary,
                    arguments: request.arguments,
                    environment: environment,
                    timeout: request.timeout,
                    maxOutputBytes: request.maxOutputBytes,
                    label: "opencodex access read")
            }
            return Data(result.stdout.utf8)
        } catch let error as OpenCodexAccessError {
            throw error
        } catch let error as SubprocessRunnerError {
            switch error {
            case .binaryNotFound: throw OpenCodexAccessError.executableMissing
            case .outputTooLarge: throw OpenCodexAccessError.outputTooLarge
            case let .nonZeroExit(code, _):
                // 2.88.0 maps RuntimeApiError(404) to 4. Other exits have no reliable typed cause.
                if code == 4 { throw OpenCodexAccessError.notFound }
                throw OpenCodexAccessError.communicationFailed
            default: throw OpenCodexAccessError.communicationFailed
            }
        } catch {
            throw OpenCodexAccessError.communicationFailed
        }
    }
}

/// Deliberately supports only the inspected published 2.88.0 layout. No PATH runtime, download, or CLI fallback.
public struct OpenCodexAccessRenameInstallation: Equatable, Sendable {
    public let executable: String
    public let runtime: String
    public let helper: String

    static var helperURL: URL? {
        CodexBarCoreResources.bundle?.url(forResource: "rename", withExtension: "mjs")
    }

    public static func resolve(executable: String) throws -> Self {
        let fm = FileManager.default
        let cli = URL(fileURLWithPath: executable).resolvingSymlinksInPath().standardizedFileURL
        let root = cli.deletingLastPathComponent().deletingLastPathComponent()
        func contained(_ path: String) throws -> URL {
            let candidate = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/"), fm.fileExists(atPath: candidate.path) else {
                throw OpenCodexAccessError.renameUnsupported
            }
            return candidate
        }
        do {
            guard cli.path == root.appendingPathComponent("bin/ocx.mjs").path,
                  fm.isExecutableFile(atPath: cli.path) else { throw OpenCodexAccessError.renameUnsupported }
            let package = try OpenCodexAccessParser.object(Data(contentsOf: contained("package.json")))
            guard package["name"] as? String == "@bitkyc08/opencodex",
                  package["version"] as? String == "2.88.0",
                  let bins = package["bin"] as? [String: String], bins["ocx"] == "./bin/ocx.mjs"
            else { throw OpenCodexAccessError.renameUnsupported }
            _ = try contained("src/cli/runtime-api.ts")
            let bunPackage = try OpenCodexAccessParser
                .object(Data(contentsOf: contained("node_modules/bun/package.json")))
            guard bunPackage["name"] as? String == "bun",
                  let dependencies = package["dependencies"] as? [String: String],
                  let bunVersion = dependencies["bun"],
                  bunPackage["version"] as? String == bunVersion else { throw OpenCodexAccessError.renameUnsupported }
            let runtime = try contained("node_modules/bun/bin/bun.exe")
            guard fm.isExecutableFile(atPath: runtime.path),
                  let helper = Self.helperURL
            else { throw OpenCodexAccessError.renameUnsupported }
            return .init(executable: cli.path, runtime: runtime.path, helper: helper.path)
        } catch {
            throw OpenCodexAccessError.renameUnsupported
        }
    }
}

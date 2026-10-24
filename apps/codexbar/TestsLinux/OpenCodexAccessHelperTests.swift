import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexAccessHelperTests {
    /// The helper runs under Node; CI images without `node` on PATH skip this test instead of failing it.
    static let nodePath: String? = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":")
        .map { String($0) + "/node" }.first { FileManager.default.isExecutableFile(atPath: $0) }

    @Test(.enabled(if: Self.nodePath != nil, "node is not on PATH"))
    func `OpenCodexAccess helper uses exact id patch and contains package runtime and output`() async throws {
        let node = try #require(Self.nodePath)
        let helper = try #require(OpenCodexAccessRenameInstallation.helperURL)
        let script = #"""
        import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, linkSync, symlinkSync, rmSync } from 'node:fs';
        import { tmpdir } from 'node:os';
        import { join, dirname } from 'node:path';
        import { execFileSync } from 'node:child_process';
        import { pathToFileURL } from 'node:url';
        import assert from 'node:assert/strict';
        const helper = process.argv[2];
        const { renameOnce } = await import(pathToFileURL(helper));
        const root = mkdtempSync(join(tmpdir(), 'access-fake-package-'));
        const createdAt = '2026-10-20T01:02:03Z';
        function fixture(mode) {
          const pkg = join(root, mode);
          mkdirSync(join(pkg, 'bin'), { recursive: true });
          mkdirSync(join(pkg, 'src/cli'), { recursive: true });
          mkdirSync(join(pkg, 'node_modules/bun/bin'), { recursive: true });
          const cli = join(pkg, 'bin/ocx.mjs');
          const runtime = join(pkg, 'node_modules/bun/bin/bun.exe');
          writeFileSync(cli, 'CLI MUST NOT EXECUTE'); chmodSync(cli, 0o755);
          linkSync(process.execPath, runtime);
          writeFileSync(join(pkg, 'package.json'), JSON.stringify({ name: '@bitkyc08/opencodex', version: '2.88.0',
            type: 'module', bin: { ocx: './bin/ocx.mjs' }, dependencies: { bun: '1.4.2' } }));
          writeFileSync(join(pkg, 'node_modules/bun/package.json'), JSON.stringify({ name: 'bun', version: '1.4.2' }));
          const source = `
            console.log('synthetic-module-secret'); console.error('synthetic-module-secret');
            export async function runtimeBaseUrl() { return 'http://localhost:4321'; }
            globalThis.fetch = async (url, init) => {
              if (url !== 'http://localhost:4321/api/keys' || init.method !== 'PATCH' || init.redirect !== 'error'
                || init.credentials !== 'omit' || init.body !== JSON.stringify({ id: 'gone-id', name: 'new' })) throw Error('synthetic-secret');
              // The selected id disappeared, while another key now has that id as its name.
              const rows = [{ id: 'another', name: 'gone-id', allowedModels: ['kept'] }];
              if ('${mode}' === 'gone') {
                const target = rows.find(row => row.id === JSON.parse(init.body).id);
                if (target || rows[0].name !== 'gone-id' || rows[0].allowedModels[0] !== 'kept') throw Error('wrong key changed');
                return new Response(JSON.stringify({ error: 'synthetic-secret' }), { status: 404 });
              }
              if ('${mode}' === 'denied') return new Response('synthetic-secret', { status: 403 });
              if ('${mode}' === 'redirect') return new Response('synthetic-secret', { status: 302, headers: { location: 'https://evil.invalid' } });
              if ('${mode}' === 'large') return new Response('x'.repeat(262145));
              if ('${mode}' === 'throw') throw Error('synthetic-secret');
              return new Response(JSON.stringify({ id: '${mode}' === 'wrong' ? 'another' : 'gone-id', name: 'new',
                createdAt: '${createdAt}', allowedProviders: ['claude'], allowedModels: ['model'], key: 'synthetic-secret' }));
            };
            export async function runtimeRequest(path, init, deps) {
              if (path !== '/api/keys' || deps.baseUrl !== 'http://localhost:4321') throw Error('synthetic-secret');
              const response = await deps.fetchImpl(deps.baseUrl + path, init);
              if (!response.ok) throw { status: response.status, body: 'synthetic-secret' };
              return response.json();
            }
          `;
          writeFileSync(join(pkg, 'src/cli/runtime-api.ts'), source);
          return { cli, runtime, pkg };
        }
        function run(f, input = JSON.stringify({ id: 'gone-id', name: 'new' })) {
          const output = execFileSync(f.runtime, [helper, f.cli], { input, encoding: 'utf8',
            env: { PATH: process.env.PATH, HOME: root, NODE_NO_WARNINGS: '1',
                DYLD_LIBRARY_PATH: join(dirname(process.execPath), '../lib') } });
          assert(!output.includes('synthetic-secret') && !output.includes('synthetic-module-secret'));
          return JSON.parse(output);
        }
        try {
          assert.deepEqual(run(fixture('success')), { id: 'gone-id', name: 'new', createdAt,
            allowedProviders: ['claude'], allowedModels: ['model'] });
          assert.deepEqual(run(fixture('gone')), { error: 'not_found' });
          assert.deepEqual(run(fixture('denied')), { error: 'permission_denied' });
          for (const mode of ['wrong', 'redirect', 'throw', 'large']) {
            assert.deepEqual(run(fixture(mode)), { error: 'confirmation_required' });
          }
          const valid = fixture('input');
          for (const input of ['{}', '{', JSON.stringify({ id: 'x', name: 'new', url: 'http://evil.invalid' }),
            JSON.stringify({ id: '', name: 'new' }), JSON.stringify({ id: 'x', name: '\nnew' }),
            JSON.stringify({ id: 'x', name: '--json' }), 'x'.repeat(4097)]) {
            assert.deepEqual(run(valid, input), { error: 'invalid_input' });
          }
          for (const [mode, relative] of [['missing-module','src/cli/runtime-api.ts'],
            ['missing-runtime','node_modules/bun/bin/bun.exe'], ['missing-package','package.json']]) {
            const f = fixture(mode); rmSync(join(f.pkg, relative));
            // missing runtime cannot launch; exercise exported validation with a synthetic runtime path.
            assert.deepEqual(await renameOnce(f.cli, f.runtime, '{"id":"x","name":"new"}'), { error: 'unsupported_installation' });
          }
          const wrong = fixture('wrong-package');
          writeFileSync(join(wrong.pkg, 'package.json'), '{"name":"other","version":"2.88.0"}');
          assert.deepEqual(run(wrong), { error: 'unsupported_installation' });
          const version = fixture('wrong-version');
          writeFileSync(join(version.pkg, 'package.json'), '{"name":"@bitkyc08/opencodex","version":"2.89.0"}');
          assert.deepEqual(run(version), { error: 'unsupported_installation' });
          const escape = fixture('escape');
          rmSync(join(escape.pkg, 'src/cli/runtime-api.ts'));
          symlinkSync(join(valid.pkg, 'src/cli/runtime-api.ts'), join(escape.pkg, 'src/cli/runtime-api.ts'));
          assert.deepEqual(run(escape), { error: 'unsupported_installation' });
          const noContract = fixture('no-contract');
          writeFileSync(join(noContract.pkg, 'src/cli/runtime-api.ts'), 'export function runtimeRequest() {}');
          assert.deepEqual(run(noContract), { error: 'unsupported_installation' });
          const noRequest = fixture('no-request');
          writeFileSync(join(noRequest.pkg, 'src/cli/runtime-api.ts'), 'export function runtimeBaseUrl() {}');
          assert.deepEqual(run(noRequest), { error: 'unsupported_installation' });
          console.log('OpenCodexAccess fake helper checks passed');
        } finally { rmSync(root, { recursive: true, force: true }); }
        """#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let driver = directory.appendingPathComponent("fake-helper-tests.mjs")
        try script.write(to: driver, atomically: true, encoding: .utf8)
        let result = try await SubprocessRunner.run(
            binary: node, arguments: [driver.path, helper.path],
            environment: ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "", "NODE_NO_WARNINGS": "1"],
            timeout: 30, maxOutputBytes: 262_144, label: "OpenCodexAccess fake helper")
        #expect(result.stdout.contains("fake helper checks passed"))
        #expect(result.stderr.isEmpty)
    }
}

extension OpenCodexAccessHelperTests {
    private static let bundledBun =
        "/opt/homebrew/lib/node_modules/@bitkyc08/opencodex/node_modules/bun/bin/bun.exe"

    @Test(
        .enabled(if: FileManager.default.isExecutableFile(atPath: Self.bundledBun)),
        .enabled(if: Self.nodePath != nil, "node is not on PATH"))
    func `OpenCodexAccess actual Bun keeps synthetic module diagnostics out of native output`() async throws {
        let node = try #require(Self.nodePath)
        let helper = try #require(OpenCodexAccessRenameInstallation.helperURL)
        let script = #"""
        import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, copyFileSync, rmSync } from 'node:fs';
        import { tmpdir } from 'node:os';
        import { join } from 'node:path';
        import { spawnSync } from 'node:child_process';
        import assert from 'node:assert/strict';
        const [helper, binary] = process.argv.slice(2);
        const root = mkdtempSync(join(tmpdir(), 'access-real-bun-fake-package-'));
        const secret = 'synthetic-bun-output-secret';
        const expected = { id: 'exact-id', name: 'new', createdAt: '2026-10-20T01:02:03Z' };
        function fixture(mode) {
          const pkg = join(root, mode);
          for (const path of ['bin', 'src/cli', 'node_modules/bun/bin']) mkdirSync(join(pkg, path), { recursive: true });
          const cli = join(pkg, 'bin/ocx.mjs');
          const runtime = join(pkg, 'node_modules/bun/bin/bun.exe');
          // Only this executable is copied from the installed package. All imports and HOME are synthetic.
          copyFileSync(binary, runtime); chmodSync(runtime, 0o755);
          writeFileSync(cli, 'throw new Error("CLI MUST NOT EXECUTE")'); chmodSync(cli, 0o755);
          writeFileSync(join(pkg, 'package.json'), JSON.stringify({ name: '@bitkyc08/opencodex', version: '2.88.0',
            type: 'module', bin: { ocx: './bin/ocx.mjs' }, dependencies: { bun: '1.4.2' } }));
          writeFileSync(join(pkg, 'node_modules/bun/package.json'), '{"name":"bun","version":"1.4.2"}');
          const diagnostics = `
            import { writeSync } from 'node:fs';
            import { Console } from 'node:console';
            function diagnostics() {
              for (const method of ['log', 'error', 'warn', 'info', 'debug', 'trace', 'dir', 'table']) console[method]('${secret}');
              const extra = new Console({ stdout: process.stdout, stderr: process.stderr });
              extra.log('${secret}'); extra.error('${secret}');
              process.stdout.write('${secret}'); process.stderr.write('${secret}');
              writeSync(1, '${secret}'); writeSync(2, '${secret}');
            }
            diagnostics();
            setTimeout(diagnostics, 1);
            export async function runtimeBaseUrl() {
              diagnostics(); return 'http://localhost:4321';
            }
            export async function runtimeRequest(path, init, deps) {
              diagnostics(); await new Promise(resolve => setTimeout(resolve, 5));
              setTimeout(diagnostics, 10); // Also attempt output after the result descriptor has closed.
              if (path !== '/api/keys' || init.method !== 'PATCH'
                || init.body !== JSON.stringify({ id: 'exact-id', name: 'new' })
                || deps.baseUrl !== 'http://localhost:4321') throw Error('contract mismatch');
              if ('${mode}' === 'throw') throw Error('${secret}');
              if ('${mode}' === 'denied') throw { status: 403, body: '${secret}' };
              return { ...${JSON.stringify(expected)}, key: '${secret}' };
            }
          `;
          writeFileSync(join(pkg, 'src/cli/runtime-api.ts'), diagnostics);
          return { cli, runtime, pkg };
        }
        try {
          for (const mode of ['success', 'throw', 'denied']) {
            const f = fixture(mode);
            const version = spawnSync(f.runtime, ['--version'], {
              encoding: 'utf8', cwd: f.pkg, env: { HOME: root, PATH: process.env.PATH }, timeout: 15000,
            });
            assert(version.status === 0 && version.stdout.trim() === '1.4.2', 'fixture must execute actual Bun 1.4.2');
            const child = spawnSync(f.runtime, [helper, f.cli], {
              input: '{"id":"exact-id","name":"new"}', encoding: 'utf8', timeout: 15000,
              cwd: f.pkg, env: { HOME: root, PATH: process.env.PATH, TMPDIR: root, NODE_NO_WARNINGS: '1' },
            });
            const cleanStdout = !child.stdout?.includes(secret);
            const cleanStderr = !child.stderr?.includes(secret);
            // Failure diagnostics report booleans only, never the synthetic body or captured output.
            assert(child.status === 0 && !child.error, `${mode}: helper did not exit successfully`);
            assert(cleanStdout && cleanStderr, `${mode}: output boundary failed (stdoutClean=${cleanStdout}, stderrClean=${cleanStderr})`);
            assert.equal(child.stderr, '', `${mode}: unexpected stderr`);
            const result = mode === 'success' ? expected : { error: mode === 'denied' ? 'permission_denied' : 'confirmation_required' };
            assert.equal(child.stdout, JSON.stringify(result) + '\n', `${mode}: only the validated envelope may reach Swift`);
          }
          const invalid = fixture('invalid');
          const child = spawnSync(invalid.runtime, [helper, invalid.cli], {
            input: '{', encoding: 'utf8', cwd: invalid.pkg, env: { HOME: root, PATH: process.env.PATH }, timeout: 15000,
          });
          assert.equal(child.status, 0);
          assert.equal(child.stdout, '{"error":"invalid_input"}\n');
          assert.equal(child.stderr, '');
          console.log('OpenCodexAccess actual Bun synthetic output boundary passed');
        } finally { rmSync(root, { recursive: true, force: true }); }
        """#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let driver = directory.appendingPathComponent("actual-bun-fake-module-tests.mjs")
        try script.write(to: driver, atomically: true, encoding: .utf8)
        let result = try await SubprocessRunner.run(
            binary: node,
            arguments: [driver.path, helper.path, Self.bundledBun],
            environment: ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "", "NODE_NO_WARNINGS": "1"],
            timeout: 60,
            maxOutputBytes: 262_144,
            label: "OpenCodexAccess actual Bun synthetic module")
        #expect(result.stdout.contains("actual Bun synthetic output boundary passed"))
        #expect(result.stderr.isEmpty)
    }
}

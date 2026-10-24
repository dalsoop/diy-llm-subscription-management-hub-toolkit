// Limited 2.88.0 adapter. No CLI import, name lookup, config writes, or authentication export.
import { realpath, readFile, stat, access } from "node:fs/promises";
import { constants, openSync, closeSync, writeSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const LIMIT = 262144;
const fail = (code) => {
  throw { accessCode: code };
};
const record = (value) => value && typeof value === "object" && !Array.isArray(value);
const text = (value) => typeof value === "string" && value.trim() && !/[\p{Cc}\p{Cf}]/u.test(value);
const instant = (value) =>
  typeof value === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value) &&
  Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString().slice(0, 19) === value.slice(0, 19);

async function installation(selectedCLI, runtimePath) {
  try {
    const cli = await realpath(selectedCLI);
    const root = dirname(dirname(cli));
    if (cli !== join(root, "bin/ocx.mjs")) fail("unsupported_installation");
    const contained = async (relative) => {
      const path = await realpath(join(root, relative));
      if (!path.startsWith(root + "/") || !(await stat(path)).isFile()) fail("unsupported_installation");
      return path;
    };
    const json = async (relative) => {
      const path = await contained(relative);
      if ((await stat(path)).size > LIMIT) fail("unsupported_installation");
      return JSON.parse(await readFile(path, "utf8"));
    };
    const pkg = await json("package.json");
    if (
      pkg.name !== "@bitkyc08/opencodex" ||
      pkg.version !== "2.88.0" ||
      pkg.bin?.ocx !== "./bin/ocx.mjs" ||
      typeof pkg.dependencies?.bun !== "string"
    )
      fail("unsupported_installation");
    const bunPkg = await json("node_modules/bun/package.json");
    if (bunPkg.name !== "bun" || bunPkg.version !== pkg.dependencies.bun) fail("unsupported_installation");
    const bun = await contained("node_modules/bun/bin/bun.exe");
    if ((await realpath(runtimePath)) !== bun) fail("unsupported_installation");
    await access(bun, constants.X_OK);
    return await contained("src/cli/runtime-api.ts");
  } catch {
    fail("unsupported_installation");
  }
}

function inputValue(input) {
  if (typeof input !== "string" || Buffer.byteLength(input) > 4096) fail("invalid_input");
  let value;
  try {
    value = JSON.parse(input);
  } catch {
    fail("invalid_input");
  }
  if (
    !record(value) ||
    Object.keys(value).sort().join(",") !== "id,name" ||
    !text(value.id) ||
    Buffer.byteLength(value.id) > 512 ||
    value.id.startsWith("-") ||
    !text(value.name) ||
    value.name !== value.name.trim() ||
    value.name.length > 64 ||
    /^[-\u2010-\u2015\u2212]/.test(value.name) ||
    /^json(?:=|$)/.test(value.name)
  )
    fail("invalid_input");
  return value;
}

function baseURL(raw) {
  const url = new URL(raw);
  if (
    !["http:", "https:"].includes(url.protocol) ||
    url.username ||
    url.password ||
    !["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) ||
    url.search ||
    url.hash ||
    url.pathname !== "/"
  )
    fail("confirmation_required");
  return url.origin;
}

/// Exported for fake-package tests; production supplies only argv-selected CLI, process.execPath, and stdin.
export async function renameOnce(selectedCLI, runtimePath, input) {
  try {
    const value = inputValue(input);
    const modulePath = await installation(selectedCLI, runtimePath);
    let api;
    try {
      api = await import(pathToFileURL(modulePath).href);
    } catch {
      fail("unsupported_installation");
    }
    if (typeof api.runtimeBaseUrl !== "function" || typeof api.runtimeRequest !== "function")
      fail("unsupported_installation");
    const base = baseURL(await api.runtimeBaseUrl());
    const body = JSON.stringify({ id: value.id, name: value.name });
    const fetchImpl = async (url, init) => {
      if (
        String(url) !== base + "/api/keys" ||
        init?.method !== "PATCH" ||
        init.body !== body ||
        init.redirect !== "error" ||
        init.credentials !== "omit"
      )
        fail("confirmation_required");
      const response = await fetch(url, init);
      if (response.redirected || (response.status >= 300 && response.status < 400)) fail("confirmation_required");
      const reader = response.body?.getReader();
      const chunks = [];
      let bytes = 0;
      if (reader) {
        try {
          for (;;) {
            const { value: chunk, done } = await reader.read();
            if (done) break;
            bytes += chunk.byteLength;
            if (bytes > LIMIT) fail("confirmation_required");
            chunks.push(Buffer.from(chunk));
          }
        } finally {
          await reader.cancel().catch(() => {});
        }
      }
      return new Response(Buffer.concat(chunks), { status: response.status, headers: response.headers });
    };
    const result = await api.runtimeRequest(
      "/api/keys",
      {
        method: "PATCH",
        body,
        redirect: "error",
        credentials: "omit",
      },
      { baseUrl: base, fetchImpl },
    );
    if (!record(result) || result.id !== value.id || result.name !== value.name || !instant(result.createdAt))
      fail("confirmation_required");
    const projected = { id: result.id, name: result.name, createdAt: result.createdAt };
    for (const scope of ["allowedProviders", "allowedModels"]) {
      if (result[scope] === undefined) continue;
      if (!Array.isArray(result[scope]) || result[scope].some((item) => !text(item) || item.length > 256))
        fail("confirmation_required");
      projected[scope] = [...result[scope]];
    }
    return projected;
  } catch (error) {
    const allowed = ["unsupported_installation", "invalid_input", "confirmation_required"];
    if (allowed.includes(error?.accessCode)) return { error: error.accessCode };
    if (error?.status === 404) return { error: "not_found" };
    if (error?.status === 401 || error?.status === 403) return { error: "permission_denied" };
    return { error: "confirmation_required" };
  }
}

function writeResult(fd, result) {
  try {
    const bytes = Buffer.from(JSON.stringify(result) + "\n");
    let offset = 0;
    while (offset < bytes.length) {
      const written = writeSync(fd, bytes, offset, bytes.length - offset);
      if (written === 0) break;
      offset += written;
    }
  } catch {
    // A broken result pipe must not turn into a raw runtime diagnostic.
  } finally {
    if (fd > 2) {
      try {
        closeSync(fd);
      } catch {
        /* Nothing may be printed here. */
      }
    }
  }
}

async function main() {
  let output;
  try {
    // Bun's native console bypasses process.stdout/stderr.write. Keep a private result descriptor,
    // then silence fd 1/2 before any package import, including Console instances and direct fs writes.
    output = openSync("/dev/fd/1", constants.O_WRONLY);
    if (output <= 2) fail("unsupported_installation");
    closeSync(1);
    if (openSync("/dev/null", constants.O_WRONLY) !== 1) fail("unsupported_installation");
    closeSync(2);
    if (openSync("/dev/null", constants.O_WRONLY) !== 2) fail("unsupported_installation");
  } catch {
    // Fail before loading the management module if isolation cannot be established.
    writeResult(output ?? 1, { error: "unsupported_installation" });
    return;
  }
  let result = { error: "invalid_input" };
  try {
    if (process.argv.length === 3) {
      let bytes = 0;
      const chunks = [];
      for await (const chunk of process.stdin) {
        bytes += chunk.byteLength;
        if (bytes > 4096) fail("invalid_input");
        chunks.push(chunk);
      }
      result = await renameOnce(process.argv[2], process.execPath, Buffer.concat(chunks).toString("utf8"));
    }
  } catch {
    /* Fixed error only. */
  }
  writeResult(output, result);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import type { TerminalReadModel, TerminalSnapshot } from "./manager";
import { RETAINED_PER_STREAM } from "./manager";

const DEFAULT_POLL_MS = 1000;
const TMUX_SESSION_PREFIX = "subagent-";

function tailBytes(buf: Buffer, maxBytes: number) {
  if (buf.byteLength <= maxBytes) return { slice: buf, truncatedBytes: 0, totalBytes: buf.byteLength };
  const start = buf.byteLength - maxBytes;
  return { slice: buf.subarray(start), truncatedBytes: start, totalBytes: buf.byteLength };
}

function safeReadTextSlice(filePath: string) {
  try {
    if (!fs.existsSync(filePath)) {
      return { text: "", totalBytes: 0, truncatedBytes: 0 };
    }
    const buf = fs.readFileSync(filePath);
    const { slice, truncatedBytes, totalBytes } = tailBytes(buf, RETAINED_PER_STREAM);
    return { text: slice.toString("utf-8"), totalBytes, truncatedBytes };
  } catch {
    return { text: "", totalBytes: 0, truncatedBytes: 0 };
  }
}

function tmuxLsSessions(tmuxBin = "tmux"): string[] {
  try {
    const res = spawnSync(tmuxBin, ["ls"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], windowsHide: true });
    const out = res.stdout ?? "";
    const lines = out.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    const names: string[] = [];
    for (const line of lines) {
      const m = /^([^:]+):/.exec(line);
      if (m?.[1] && (m[1].startsWith("subagent-") || m[1].startsWith("pi-subagent-"))) names.push(m[1]);
    }
    return names;
  } catch {
    return [];
  }
}

function sessionToPaths(sessionName: string) {
  const base = path.join(os.tmpdir(), sessionName);
  return {
    stdoutPath: `${base}-stdout.log`,
    stderrPath: `${base}-stderr.log`,
    codePath: `${base}-code.txt`,
  };
}

type TmuxPseudoMeta = {
  sessionName: string;
  id: string;
};

export function createTmuxSubagentReadModel(options: {
  defaultCwd: string;
  tmuxBin?: string;
  pollMs?: number;
}) {
  const tmuxBin = options.tmuxBin ?? "tmux";
  const pollMs = options.pollMs ?? DEFAULT_POLL_MS;

  const listeners = new Set<() => void>();
  const idListeners = new Map<string, Set<() => void>>();

  // cache: pseudo snapshot id -> live snapshot
  const cache = new Map<string, TerminalSnapshot & { __sessionName: string }>();

  let timer: NodeJS.Timeout | undefined;
  let disposed = false;

  const notify = (id?: string) => {
    for (const l of [...listeners]) {
      try {
        l();
      } catch {
        // ignore
      }
    }
    if (id) {
      const set = idListeners.get(id);
      if (set) {
        for (const l of [...set]) {
          try {
            l();
          } catch {
            // ignore
          }
        }
      }
    }
  };

  const refresh = () => {
    if (disposed) return;
    const sessions = tmuxLsSessions(tmuxBin);

    // Drop any cache entries whose session is no longer present.
    const sessionSet = new Set(sessions);
    for (const [id, snap] of cache.entries()) {
      if (!sessionSet.has((snap as any).__sessionName)) {
        cache.delete(id);
        notify(id);
      }
    }

    for (const sessionName of sessions) {
      const metaId = `tmx-${sessionName}`;
      const { stdoutPath, stderrPath, codePath } = sessionToPaths(sessionName);

      let status: TerminalSnapshot["status"] = "running";
      let exitCode: number | undefined;
      let signal: string | undefined;
      let settledAt: number | undefined;

      if (fs.existsSync(codePath)) {
        status = "done";
        try {
          const raw = fs.readFileSync(codePath, "utf8").trim();
          const parsed = Number.parseInt(raw, 10);
          if (Number.isFinite(parsed)) {
            exitCode = parsed;
            if (parsed !== 0) {
              status = "failed";
            }
          }
        } catch {
          status = "failed";
        }
        settledAt = Date.now();
      }

      const stdoutViewRaw = safeReadTextSlice(stdoutPath);
      const stderrViewRaw = safeReadTextSlice(stderrPath);

      // createdAt: best-effort stat.
      let createdAt = Date.now();
      try {
        const s = fs.existsSync(stdoutPath)
          ? fs.statSync(stdoutPath)
          : fs.existsSync(stderrPath)
            ? fs.statSync(stderrPath)
            : null;
        if (s) createdAt = s.mtimeMs;
      } catch {
        // ignore
      }

      const snapshot: TerminalSnapshot & { __sessionName: string } = {
        id: metaId,
        __sessionName: sessionName as any,
        command: "subagent",
        title: sessionName,
        cwd: options.defaultCwd,
        pid: undefined,
        status,
        createdAt,
        settledAt,
        exitCode: exitCode,
        signal,
        errorText: status === "failed" ? "Subagent failed (non-zero exit)" : undefined,
        stdout: {
          text: stdoutViewRaw.text,
          totalBytes: stdoutViewRaw.totalBytes,
          truncatedBytes: stdoutViewRaw.truncatedBytes,
          spillPath: undefined,
        },
        stderr: {
          text: stderrViewRaw.text,
          totalBytes: stderrViewRaw.totalBytes,
          truncatedBytes: stderrViewRaw.truncatedBytes,
          spillPath: undefined,
        },
      };

      const prev = cache.get(metaId);
      cache.set(metaId, snapshot);
      if (!prev) notify(metaId);
    }
  };

  timer = setInterval(refresh, pollMs);
  refresh();

  const view: TerminalReadModel = {
    list: () => [...cache.values()],
    get: (id: string) => cache.get(id),
    size: () => cache.size,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    subscribeTo: (id, listener) => {
      let set = idListeners.get(id);
      if (!set) {
        set = new Set();
        idListeners.set(id, set);
      }
      set.add(listener);
      return () => {
        set?.delete(listener);
        if (set && set.size === 0) idListeners.delete(id);
      };
    },
    requestKill: (id) => {
      const snap = cache.get(id);
      if (!snap) return;
      const sessionName = (snap as any).__sessionName as string;
      try {
        spawnSync(tmuxBin, ["kill-session", "-t", sessionName], { stdio: ["ignore", "ignore", "ignore"], shell: false, windowsHide: true });
      } catch {
        // ignore
      }
    },
    setOnSettled: (_hook) => {
      // no-op for pseudo view
    },
  };

  return {
    view,
    dispose: () => {
      disposed = true;
      if (timer) clearInterval(timer);
      timer = undefined;
      cache.clear();
      for (const l of [...listeners]) {
        listeners.delete(l);
      }
      idListeners.clear();
    },
  };
}

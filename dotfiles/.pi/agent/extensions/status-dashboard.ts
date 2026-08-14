import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth, type Focusable, matchesKey } from "@earendil-works/pi-tui";
import * as fs from "node:fs";
import * as path from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

function formatTokens(count: number): string {
  if (!Number.isFinite(count) || count <= 0) return "0";
  if (count < 1_000) return `${Math.round(count)}`;
  if (count < 10_000) return `${(count / 1_000).toFixed(1)}k`;
  if (count < 1_000_000) return `${Math.round(count / 1_000)}k`;
  return `${(count / 1_000_000).toFixed(1)}M`;
}

function formatCost(cost: number): string {
  if (!Number.isFinite(cost) || cost <= 0) return "$0.000";
  if (cost < 0.01) return `$${cost.toFixed(4)}`;
  if (cost < 10) return `$${cost.toFixed(3)}`;
  return `$${cost.toFixed(2)}`;
}

function shortenPath(input: string): string {
  const normalized = input.replace(/\\/g, "/");
  const home = process.env.USERPROFILE?.replace(/\\/g, "/") || process.env.HOME?.replace(/\\/g, "/") || "";
  if (home && normalized.toLowerCase().startsWith(home.toLowerCase())) {
    return `~${normalized.slice(home.length)}`;
  }
  return normalized;
}

function sumUsage(ctx: any): { input: number; output: number; cost: number } {
  let input = 0;
  let output = 0;
  let cost = 0;

  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry?.type !== "message") continue;
    const usage = entry.message?.usage;
    if (!usage) continue;

    input += usage.input ?? 0;
    output += usage.output ?? 0;
    cost += usage.cost?.total ?? 0;
  }

  return { input, output, cost };
}

function summarizeSubagentArgs(args: any): string {
  if (Array.isArray(args?.chain) && args.chain.length > 0) {
    return `chain ${args.chain.map((step: any) => step?.agent || "?").join("→")}`;
  }
  if (Array.isArray(args?.tasks) && args.tasks.length > 0) {
    return `parallel ${args.tasks.map((task: any) => task?.agent || "?").join(",")}`;
  }
  if (typeof args?.agent === "string" && args.agent.trim()) {
    return args.agent.trim();
  }
  return "subagent";
}

function summarizeSubagentDetails(details: any): string | undefined {
  const mode = details?.mode;
  const results = Array.isArray(details?.results) ? details.results : [];
  if (results.length === 0) return undefined;

  const running = results.filter((result: any) => result?.exitCode === -1);
  const done = results.filter((result: any) => result?.exitCode !== -1).length;

  if (mode === "chain") {
    const current = running[0]?.agent || results[Math.min(done, results.length - 1)]?.agent;
    return current ? `chain ${done}/${results.length} ${current}` : `chain ${done}/${results.length}`;
  }

  if (mode === "parallel") {
    const names = running.map((result: any) => result?.agent).filter(Boolean);
    if (names.length > 0) {
      return `parallel ${done}/${results.length} ${names.join(", ")}`;
    }
    return `parallel ${done}/${results.length}`;
  }

  return results[0]?.agent || "subagent";
}

function centerLine(text: string, width: number): string {
  const clipped = truncateToWidth(text, width);
  const padding = Math.max(0, Math.floor((width - visibleWidth(clipped)) / 2));
  return `${" ".repeat(padding)}${clipped}`;
}

type SubagentsSnapshot = {
  main: boolean;
  subagents: Array<{ toolCallId: string; summary: string }>;
};

class SubagentsModal implements Focusable {
  readonly width = 72;
  focused = false;

  private theme: any;
  private done: (result: undefined) => void;
  private snapshot: SubagentsSnapshot;

  constructor(theme: any, done: (result: undefined) => void, snapshot: SubagentsSnapshot) {
    this.theme = theme;
    this.done = done;
    this.snapshot = snapshot;
  }

  handleInput(data: string): void {
    if (matchesKey(data, "escape")) this.done(undefined);
  }

  render(_width: number): string[] {
    const w = this.width;
    const th = this.theme;
    const innerW = w - 2;

    const pad = (s: string, len: number) => {
      const vis = visibleWidth(s);
      return s + " ".repeat(Math.max(0, len - vis));
    };

    const row = (content: string) => th.fg("border", "│") + pad(content, innerW) + th.fg("border", "│");

    const lines: string[] = [];
    lines.push(th.fg("border", `╭${"─".repeat(innerW)}╮`));
    lines.push(row(` ${th.fg("accent", "Subagents")}`));
    lines.push(row(""));

    if (!this.snapshot.main && this.snapshot.subagents.length === 0) {
      lines.push(row(` ${th.fg("muted", "No running subagents.")}`));
      lines.push(row(""));
    } else {
      if (this.snapshot.main) lines.push(row(` ${th.fg("accent", "● main")}`));
      for (const s of this.snapshot.subagents) {
        const summary = s.summary || "subagent";
        const left = `${th.fg("warning", "◉")} ${summary}`;
        lines.push(row(` ${truncateToWidth(left, innerW - 1)}`));
      }
      lines.push(row(""));
    }

    lines.push(row(` ${th.fg("dim", "Esc to close")}`));
    lines.push(th.fg("border", `╰${"─".repeat(innerW)}╯`));
    return lines;
  }

  invalidate(): void {}
  dispose(): void {}
}

export default function (pi: ExtensionAPI) {
  let mainRunning = false;
  let currentModel = "no-model";
  let currentThinking = "off";
  let currentContextWindow = 0;
  const activeSubagents = new Map<string, string>();
  let requestRender = () => {};

  const rerender = () => requestRender();

  const syncModelState = (ctx: any) => {
    currentModel = ctx.model?.id || "no-model";
    currentThinking = ctx.thinkingLevel || "off";
    currentContextWindow = ctx.model?.contextWindow ?? 0;
  };

  const getActiveAgentSummary = () => {
    const subagents = Array.from(activeSubagents.values()).filter(Boolean);
    if (subagents.length > 0) {
      return { main: mainRunning, subagents };
    }
    return { main: mainRunning, subagents: [] as string[] };
  };

  pi.registerCommand("subagents", {
    description: "Show currently running subagents",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/subagents is available in interactive mode", "warning");
        return;
      }

      const snapshot: SubagentsSnapshot = {
        main: mainRunning,
        subagents: Array.from(activeSubagents.entries()).map(([toolCallId, summary]) => ({
          toolCallId,
          summary,
        })),
      };

      await ctx.ui.custom<undefined>(
        (_tui, theme, _keybindings, done) => new SubagentsModal(theme, done, snapshot),
        { overlay: true },
      );
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    syncModelState(ctx);

    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRender = () => tui.requestRender();
      const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

      const separator = theme.fg("dim", "  |  ");

      return {
        dispose() {
          unsubscribe();
        },
        invalidate() {},
        render(width: number): string[] {
          syncModelState(ctx);

          const branch = footerData.getGitBranch();
          const cwd = theme.fg("accent", shortenPath(ctx.cwd));
          const branchText = branch ? theme.fg("success", ` (${branch})`) : "";
          const agents = getActiveAgentSummary();
          const usage = sumUsage(ctx);
          const contextUsage = ctx.getContextUsage?.();
          const usedTokens = contextUsage?.tokens ?? 0;
          const maxTokens = currentContextWindow;
          const contextPercent = maxTokens > 0 ? Math.round((usedTokens / maxTokens) * 100) : 0;
          const contextText =
            maxTokens > 0
              ? `${formatTokens(usedTokens)}/${formatTokens(maxTokens)} ${contextPercent}%`
              : formatTokens(usedTokens);
          const modelText =
            currentThinking && currentThinking !== "off"
              ? `${currentModel} (${currentThinking})`
              : `${currentModel} (off)`;

          const mainLine = [
            `${cwd}${branchText}`,
            theme.fg("text", `↑${formatTokens(usage.input)}`),
            theme.fg("text", `↓${formatTokens(usage.output)}`),
            theme.fg(contextPercent >= 85 ? "warning" : "text", contextText),
            theme.fg(usage.cost > 0 ? "warning" : "muted", formatCost(usage.cost)),
            theme.fg("accent", modelText),
          ].join(separator);

          if (!agents.main && agents.subagents.length === 0) {
            return [truncateToWidth(mainLine, width)];
          }

          const segments: string[] = [];
          if (agents.main) {
            segments.push(`${theme.fg("accent", "●")} ${theme.fg("text", "main")}`);
          }
          for (const subagent of agents.subagents) {
            segments.push(`${theme.fg("warning", "◉")} ${theme.fg("text", subagent)}`);
          }

          const agentLine = centerLine(segments.join(theme.fg("dim", "     ")), width);

          return [truncateToWidth(mainLine, width), agentLine];
        },
      };
    });

    rerender();
  });

  pi.on("agent_start", async (_event, _ctx) => {
    mainRunning = true;
    rerender();
  });

  pi.on("agent_settled", async (_event, _ctx) => {
    mainRunning = false;
    activeSubagents.clear();
    rerender();
  });

  pi.on("model_select", async (_event, ctx) => {
    syncModelState(ctx);
    rerender();
  });

  pi.on("thinking_level_select", async (_event, ctx) => {
    syncModelState(ctx);
    rerender();
  });

  pi.on("tool_execution_start", async (event, _ctx) => {
    if (event.toolName === "subagent") {
      activeSubagents.set(event.toolCallId, summarizeSubagentArgs(event.args));
      rerender();
    }
  });

  pi.on("tool_execution_update", async (event, _ctx) => {
    if (event.toolName !== "subagent") return;
    const summary = summarizeSubagentDetails((event.partialResult as any)?.details);
    if (summary) {
      activeSubagents.set(event.toolCallId, summary);
      rerender();
    }
  });

  pi.on("tool_execution_end", async (event, _ctx) => {
    if (event.toolName === "subagent") {
      activeSubagents.delete(event.toolCallId);
      rerender();
    }
  });
}

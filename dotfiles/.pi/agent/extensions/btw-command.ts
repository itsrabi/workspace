import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("btw", {
    description: "Ask a side-question via the btw-agent subagent",
    handler: async (args, ctx) => {
      const question = args.trim();
      if (!question) {
        if (ctx.hasUI) ctx.ui.notify("Usage: /btw <question>", "warning");
        return;
      }

      const prompt = [
        'Use the subagent tool in single mode with agent "btw-agent".',
        `Set cwd to ${ctx.cwd}.`,
        "Ask it to answer this focused side-question independently and concisely:",
        "",
        question,
        "",
        'Return the subagent answer directly. Do not do the work yourself unless the subagent tool is unavailable.',
      ].join("\n");

      if (ctx.hasUI) {
        ctx.ui.notify(`Dispatching btw-agent: ${question}`, "info");
      }

      if (ctx.isIdle()) {
        pi.sendUserMessage(prompt);
      } else {
        pi.sendUserMessage(prompt, { deliverAs: "followUp" });
      }
    },
  });
}

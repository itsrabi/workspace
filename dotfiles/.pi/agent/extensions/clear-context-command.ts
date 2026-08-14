import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.registerCommand("clear", {
		description: "Clear the current conversation context (empty the active session history)",
		handler: async (_args, ctx) => {
			// Avoid interrupting an active run; just tell the user.
			if (!ctx.isIdle?.()) {
				await ctx.ui.notify("/clear: wait for the current run to finish (agent not idle).", "warning");
				return;
			}

			const ok = await ctx.ui.confirm(
				"Clear context?",
				"This will remove all messages from the active session so the next prompt starts from a clean context window.",
			);
			if (!ok) return;

			try {
				ctx.sessionManager.newSession();
				ctx.ui.notify("Context cleared.", "success");
			} catch (err) {
				ctx.ui.notify(`/clear failed: ${err instanceof Error ? err.message : String(err)}`, "error");
			}
		},
	});
}

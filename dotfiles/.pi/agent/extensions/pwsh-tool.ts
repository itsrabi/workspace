import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawnSync } from "node:child_process";
import * as os from "node:os";

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "pwsh",
		label: "PowerShell",
		description: "Run a PowerShell (pwsh) command/script on this Windows host. Returns stdout/stderr.",
		parameters: Type.Object({
			command: Type.String({
				description:
					"PowerShell command or script to run. Will be executed with: powershell -NoProfile -ExecutionPolicy Bypass -Command <command>.",
			}),
			cwd: Type.Optional(Type.String({ description: "Working directory for the command." })),
			requireSuccess: Type.Optional(Type.Boolean({ description: "If true, treat non-zero exit codes as an error." })),
		}),
		async execute(toolCallId, params, _signal, _onUpdate, ctx) {
			const command = params.command;
			const cwd = params.cwd ?? ctx.cwd ?? os.homedir();
			const requireSuccess = params.requireSuccess ?? false;

			// Prefer pwsh.exe when available; fall back to powershell.exe.
			const powershellExe = process.env.PWSH ?? "pwsh";
			const res = spawnSync(
				powershellExe,
				[
					"-NoProfile",
					"-ExecutionPolicy",
					"Bypass",
					"-Command",
					command,
				],
				{
						cwd,
						encoding: "utf8",
						maxBuffer: 10 * 1024 * 1024,
					},
			);

			const stdout = (res.stdout ?? "").toString();
			const stderr = (res.stderr ?? "").toString();
			const code = res.status ?? 0;

			if (requireSuccess && code !== 0) {
				return {
					content: [
						{
							type: "text",
							text: `Command failed (exit code ${code}).\n\nSTDERR:\n${stderr || "(empty)"}`,
						},
					],
					details: { code, stdout, stderr },
				};
			}

			const textParts: string[] = [];
			if (stdout.trim().length > 0) textParts.push(stdout.trimEnd());
			if (stderr.trim().length > 0) textParts.push(`STDERR:\n${stderr.trimEnd()}`);
			const text = textParts.join("\n\n") || `Command produced no output (exit code ${code}).`;

			return {
				content: [{ type: "text", text }],
				details: { code, stdout, stderr, cwd },
			};
		},
	});
}

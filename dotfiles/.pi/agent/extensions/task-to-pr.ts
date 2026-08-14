import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createAgentSession, ModelRuntime, SessionManager } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { randomInt } from "node:crypto";

function runGit(
	cwd: string,
	args: string[],
	opts?: { env?: NodeJS.ProcessEnv; timeoutMs?: number }
) {
	const res = spawnSync("git", args, {
		cwd,
		encoding: "utf8",
		env: { ...process.env, GIT_TERMINAL_PROMPT: "0", ...(opts?.env ?? {}) },
		// Never allow git to wait for interactive stdin.
		stdio: ["ignore", "pipe", "pipe"],
		timeout: opts?.timeoutMs ?? 120000,
	});
	if (res.error) {
		throw res.error;
	}
	const stdout = (res.stdout ?? "").toString().trim();
	const stderr = (res.stderr ?? "").toString().trim();
	return { code: res.status ?? 0, stdout, stderr };
}

function hasGitRepo(cwd: string) {
	const res = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], { cwd, encoding: "utf8" });
	return (res.status ?? 1) === 0;
}

function slugify(input: string) {
	return input
		.trim()
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.slice(0, 48);
}

function firstJsonObject(text: string) {
	const start = text.indexOf("{");
	if (start === -1) return null;
	// crude but works for simple payloads
	const end = text.lastIndexOf("}");
	if (end === -1 || end <= start) return null;
	const candidate = text.slice(start, end + 1);
	try {
		return JSON.parse(candidate);
	} catch {
		return null;
	}
}

function getLastAssistantText(messages: any[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i];
		if (!m || m.role !== "assistant") continue;
		const content = m.content;
		if (typeof content === "string") return content;
		if (Array.isArray(content)) {
			const textBlocks = content.filter((b: any) => b?.type === "text" && typeof b.text === "string");
			if (textBlocks.length > 0) return textBlocks.map((b: any) => b.text).join("\n").trim();
		}
	}
	return "";
}

function parseRepoFromOriginUrl(url: string): { owner: string; repo: string } | null {
	// git@github.com:owner/repo.git
	let m = url.match(/git@github\.com:([^/]+)\/([^/]+?)(?:\.git)?$/i);
	if (m) return { owner: m[1], repo: m[2] };
	// https://github.com/owner/repo(.git)
	m = url.match(/https?:\/\/github\.com\/([^/]+)\/([^/]+?)(?:\.git)?$/i);
	if (m) return { owner: m[1], repo: m[2] };
	return null;
}

function isCmdAvailable(cmd: string) {
	const res = spawnSync(cmd, ["--version"], {
		encoding: "utf8",
		stdio: "ignore",
		timeout: 5000,
	});
	return (res.status ?? 1) === 0;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("task-to-pr", {
		description:
			"Create a PR from a task: distill requirements, create a new branch, implement changes, commit, push, and open a GitHub PR. Stashes existing changes if needed.",
		handler: async (args, ctx) => {
			const task = String(args ?? "").trim();
			if (!task) {
				ctx.ui?.notify?.("Usage: /task-to-pr <task>", "warning");
				return;
			}

			const cwd = ctx.cwd;
			if (!cwd || !hasGitRepo(cwd)) {
				ctx.ui?.notify?.("/task-to-pr: not inside a git repository", "error");
				return;
			}

			// Make sure we don't step on an active run.
			if (typeof (ctx as any).isIdle === "function" && !(ctx as any).isIdle()) {
				ctx.ui?.notify?.("/task-to-pr: wait until Pi is idle", "warning");
				return;
			}

			const originalBranchRes = runGit(cwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
			const originalBranch = originalBranchRes.stdout;
			if (!originalBranch || originalBranch === "HEAD") {
				ctx.ui?.notify?.("/task-to-pr: detached HEAD is not supported (please checkout a branch)", "error");
				return;
			}

			const status = runGit(cwd, ["status", "--porcelain"]);
			const hasChanges = status.stdout.length > 0;

			let stashMade = false;

			if (hasChanges) {
				const stashMessage = `pi-task-to-pr-${Date.now()}`;
				const stashRes = runGit(cwd, ["stash", "push", "-u", "-m", stashMessage]);
				stashMade = stashRes.code === 0;
			}

			// Determine base branch from origin/HEAD if possible.
			let baseBranch = "main";
			{
				const head = runGit(cwd, ["symbolic-ref", "refs/remotes/origin/HEAD"]);
				if (!head.stderr && head.stdout) {
					const parts = head.stdout.split("/");
					baseBranch = parts[parts.length - 1] || baseBranch;
				} else {
					// Fallback: parse `git remote show origin`.
					const show = runGit(cwd, ["remote", "show", "origin"]);
					const m = show.stdout.match(/HEAD branch:\s*([^\s]+)/i);
					if (m?.[1]) baseBranch = m[1];
				}
			}

			// Ask an AGENT to generate the branch name (NOT git SHA).
			const randomSuffix = String(randomInt(1000, 9999));

			const modelRuntime = await ModelRuntime.create();

			// 1) Ask an AGENT to generate the branch name.
			// Use read-only tools to avoid accidental repo edits during naming.
			const { session: branchSession } = await createAgentSession({
				cwd,
				sessionManager: SessionManager.inMemory(cwd),
				modelRuntime,
				tools: ["read"],
			});

			const branchNamePrompt = [
				"You are an automation agent whose ONLY job is to produce a unique, valid git branch name.",
				"Do NOT modify repository files.",
				"Do NOT include git SHAs or any deterministic hash.",
				"Requirements for your branchName:",
				"- Must start with: pi/task-to-pr/",
				"- Must be lowercase, and contain only [a-z0-9/_-] characters",
				"- Must include the provided randomSuffix exactly once as the last path segment",
				"- The part before the suffix should be a short slug derived from the task",
				"- Keep it reasonably short (<= 100 chars)",
				"",
				`Task: ${task}`,
				`randomSuffix: ${randomSuffix}`,
				"",
				"Output STRICT JSON only with this schema:",
				"{\n  branchName: string\n}",
			].join("\n");

			await branchSession.prompt(branchNamePrompt);
			const branchText = getLastAssistantText(branchSession.messages as any);
			const branchParsed = firstJsonObject(branchText);

			let newBranch: string = branchParsed?.branchName ? String(branchParsed.branchName) : `pi/task-to-pr/${slugify(task)}-${randomSuffix}`;
			if (!newBranch.startsWith("pi/task-to-pr/")) {
				newBranch = `pi/task-to-pr/${slugify(newBranch)}-${randomSuffix}`;
			}

			// Hard validation: must end with -<randomSuffix> and include it exactly once.
			const requiredSuffix = `-${randomSuffix}`;
			const suffixOccurrences = newBranch.split(randomSuffix).length - 1;
			if (!newBranch.endsWith(requiredSuffix) || suffixOccurrences !== 1) {
				newBranch = `pi/task-to-pr/${slugify(task)}-${randomSuffix}`;
			}

			// Trim/sanitize just in case.
			newBranch = newBranch.replace(/[^a-zA-Z0-9/_-]/g, "-").toLowerCase();
			newBranch = newBranch.slice(0, 100);

			ctx.ui?.notify?.(`/task-to-pr: working... creating branch ${newBranch}`, "info");

			// Create branch from current HEAD (after stashing so worktree is clean)
			let checkoutCode = runGit(cwd, ["checkout", "-b", newBranch]).code;
			if (checkoutCode !== 0) {
				// Extremely unlikely collision; fall back to adding a second short random number.
				const retrySuffix = String(randomInt(10, 99));
				newBranch = `${newBranch}-${retrySuffix}`.slice(0, 100);
				runGit(cwd, ["checkout", "-b", newBranch]);
			}

			// 2) Now that the branch exists, create an agent that can edit files.
			// Keep bash disabled to avoid long-running shell searches; allow find/grep/ls for discovery.
			const { session: implSession } = await createAgentSession({
				cwd,
				sessionManager: SessionManager.inMemory(cwd),
				modelRuntime,
				tools: ["read", "edit", "write", "ls", "find", "grep", ...(isCmdAvailable("bash") ? ["bash"] : []), ...(isCmdAvailable("pwsh") ? ["pwsh"] : [])],
			});

			try {
				const prompt = [
					"You are an automation agent implementing a user-requested change in the current git repository.",
					"Steps:",
					"1) Distill the user task into a short requirements list.",
					"2) Make the code changes needed to satisfy the requirements. Prefer minimal, correct diffs.",
					"3) If tests are discoverable (npm/yarn/pnpm/python/go/etc), run the most relevant ones (best-effort).",
					"4) Stage nothing by yourself; just write the correct working tree changes.",
					"",
					"User task:",
					task,
					"",
					"Output STRICT JSON only with this schema:",
					"{\n  title: string,\n  body: string,\n  requirements: string[],\n  filesChanged: string[]\n}",
					"",
					"Title should be a conventional PR title (short imperative sentence).",
					"Body should include requirements and any notes about tests run.",
					"filesChanged should be paths relative to repo root.",
				].join("\n");

				await implSession.prompt(prompt);
				const text = getLastAssistantText(implSession.messages as any);
				const parsed = firstJsonObject(text);

				const title: string = parsed?.title ? String(parsed.title) : `Task: ${task}`.slice(0, 70);
				const body: string = parsed?.body ? String(parsed.body) : `Automated PR for task: ${task}`;

				ctx.ui?.notify?.(`/task-to-pr: committing changes...`, "info");

				// Stage + commit if there are changes
				runGit(cwd, ["add", "-A"]);
				const diffCached = runGit(cwd, ["diff", "--cached", "--quiet"]);
				if (diffCached.code === 0) {
					ctx.ui?.notify?.("/task-to-pr: no changes detected after the task; aborting PR creation", "warning");
					return;
				}

				runGit(cwd, ["commit", "-m", `task-to-pr: ${title}`]);

				ctx.ui?.notify?.(`/task-to-pr: pushing branch...`, "info");
				runGit(cwd, ["push", "-u", "origin", newBranch]);

				const repoUrl = runGit(cwd, ["remote", "get-url", "origin"]).stdout;
				const repo = parseRepoFromOriginUrl(repoUrl);
				if (!repo) {
					ctx.ui?.notify?.("/task-to-pr: could not parse GitHub repo from origin URL; skipping PR creation", "warning");
					return;
				}

				const ownerRepo = `${repo.owner}/${repo.repo}`;
				const ghToken = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;

				let prUrl: string | null = null;
				if (isCmdAvailable("gh")) {
					const env: any = { ...process.env };
					if (ghToken) env.GH_TOKEN = ghToken;

					ctx.ui?.notify?.(
						`/task-to-pr: gh pr create (repo=${ownerRepo}, base=${baseBranch}, head=${newBranch})`,
						"info"
					);

					const res = spawnSync(
						"gh",
						["pr", "create", "--repo", ownerRepo, "--title", title, "--body", body, "--base", baseBranch, "--head", newBranch],
						{
							cwd,
							encoding: "utf8",
							env,
							// Ensure `gh` never waits for interactive stdin prompts.
							stdio: ["ignore", "pipe", "pipe"],
							timeout: 120000,
						}
					);

					if ((res.status ?? 1) === 0) {
						// gh prints the PR URL
						const createStdout = (res.stdout ?? "").toString().trim();
						const createStderr = (res.stderr ?? "").toString().trim();
						prUrl = createStdout.split(/\s+/).find((s) => s.startsWith("http")) ?? null;
						if (createStdout) ctx.ui?.notify?.(`/task-to-pr: gh pr create stdout: ${createStdout}`, "info");
						if (createStderr) ctx.ui?.notify?.(`/task-to-pr: gh pr create stderr: ${createStderr}`, "info");
					} else {
						// If the PR already exists (e.g. rerun), fetch its URL instead of failing silently.
						const createStdout = (res.stdout ?? "").toString().trim();
						const createStderr = (res.stderr ?? "").toString().trim();
						ctx.ui?.notify?.(
							`/task-to-pr: gh pr create failed (${res.status ?? 1}). stdout=${createStdout || ""} stderr=${createStderr || ""}`.trim(),
							"warning"
						);
					}

					const viewRes = spawnSync(
						"gh",
						["pr", "view", "--repo", ownerRepo, "--head", newBranch, "--json", "url", "--jq", ".url"],
						{ cwd, encoding: "utf8", env, stdio: ["ignore", "pipe", "pipe"], timeout: 120000 }
					);

					if ((viewRes.status ?? 1) === 0) {
						const url = (viewRes.stdout ?? "").toString().trim();
						if (url.startsWith("http")) prUrl = url;
					}
				} else if (ghToken) {
					// Fallback: GitHub REST API
					const r = await fetch(`https://api.github.com/repos/${ownerRepo}/pulls`, {
						method: "POST",
						headers: {
							"content-type": "application/json",
							authorization: `Bearer ${ghToken}`,
							"user-agent": "pi-task-to-pr",
						},
						body: JSON.stringify({
							title,
							body,
							head: newBranch,
							base: baseBranch,
						}),
					});

					if (!r.ok) {
						const t = await r.text();
						throw new Error(`GitHub PR create failed (${r.status}): ${t}`);
					}

					const data: any = await r.json();
					prUrl = data?.html_url ?? null;
				} else {
					ctx.ui?.notify?.("/task-to-pr: install/login `gh` or set GITHUB_TOKEN to create a PR", "warning");
				}

				if (prUrl) {
					ctx.ui?.notify?.(`/task-to-pr: PR created: ${prUrl}`, "success");
				} else {
					ctx.ui?.notify?.(`/task-to-pr: branch pushed. Create a PR manually from ${newBranch}.`, "info");
				}
			} finally {
				// Restore stash and switch back to original branch.
				try {
					runGit(cwd, ["checkout", originalBranch]);
					if (stashMade) {
						// Restore best-effort: stash pop by message isn't supported directly; pop latest.
						runGit(cwd, ["stash", "pop"]);
					}
				} catch {
					// Do not fail PR creation cleanup.
				}
			}
		},
	});
}

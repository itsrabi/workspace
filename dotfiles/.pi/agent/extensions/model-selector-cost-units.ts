import { realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { Spacer, Text } from "@earendil-works/pi-tui";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const UPDATE_LIST_PATCH = Symbol.for("pi-model-selector-x:update-list-patch");
const THEME_KEY = Symbol.for("@earendil-works/pi-coding-agent:theme");
const APIKEY_CACHE = Symbol.for("pi-model-selector-x:apikey-cache");

function getTheme() {
	return (globalThis as any)[THEME_KEY] as any;
}

function maskApiKey(key: unknown) {
	if (!key || typeof key !== "string") return null;
	const k = key.trim();
	if (k.length === 0) return null;
	if (k.length <= 8) return "*".repeat(k.length);
	const head = k.slice(0, 6);
	const tail = k.slice(-4);
	return `${head}…${tail}`;
}

function getApiKeyCache(selector: any) {
	let cache = selector[APIKEY_CACHE];
	if (!cache) {
		cache = new Map();
		selector[APIKEY_CACHE] = cache;
	}
	return cache;
}

function resolveApiKeyDisplay(selector: any, model: any) {
	const registry = selector.modelRegistry;
	if (!registry?.getApiKeyAndHeaders) return null;
	const cache = getApiKeyCache(selector);
	const key = `${model.provider}:${model.id}`;
	if (cache.has(key)) return cache.get(key);

	cache.set(key, { state: "loading" });
	Promise.resolve()
		.then(() => registry.getApiKeyAndHeaders(model))
		.then((result: any) => {
			if (result?.ok && result.apiKey) {
				cache.set(key, {
					state: "ok",
					masked: maskApiKey(result.apiKey),
					len: result.apiKey.length,
				});
			} else if (result?.ok) {
				cache.set(key, { state: "none" });
			} else {
				cache.set(key, { state: "error", error: result?.error || "unknown" });
			}
			selector.tui?.requestRender?.();
		})
		.catch((err: any) => {
			cache.set(key, { state: "error", error: err?.message || String(err) });
			selector.tui?.requestRender?.();
		});

	return { state: "loading" };
}

function formatContextWindow(tokens: number) {
	if (!tokens) return null;
	if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
	if (tokens >= 1000) return `${Math.round(tokens / 1000)}k`;
	return String(tokens);
}

function formatMaxTokens(tokens: number) {
	if (!tokens) return null;
	if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
	if (tokens >= 1000) return `${Math.round(tokens / 1000)}k`;
	return String(tokens);
}

function formatCostNum(value: number) {
	if (!value) return "0";
	if (value < 0.01) return value.toFixed(3);
	if (value < 1) return value.toFixed(2);
	if (value < 10) return value.toFixed(1);
	return Math.round(value).toString();
}

function formatProtocolShort(api: string | undefined) {
	if (!api) return null;
	const map: Record<string, string> = {
		"openai-responses": "resp",
		"openai-completions": "comp",
		"anthropic-messages": "anth",
	};
	return map[api] || api.slice(0, 5);
}

function formatInputShort(input: string[] | undefined) {
	if (!input || input.length === 0) return "txt";
	const parts: string[] = [];
	if (input.includes("text")) parts.push("txt");
	if (input.includes("image")) parts.push("img");
	if (input.includes("audio")) parts.push("aud");
	return parts.join("+") || "txt";
}

function formatCostWithUnits(cost: any) {
	if (!cost) return null;
	const { input, output, cacheRead, cacheWrite } = cost;
	if (!input && !output) {
		return { label: "free", isFree: true, input, output, cacheRead, cacheWrite };
	}

	// pi model registry stores costs as USD per 1,000,000 tokens.
	// (See packages/ai/src/models.ts calculateCost => model.cost.* / 1_000_000)
	return {
		label: `Input $${formatCostNum(input)} / 1M tokens · Output $${formatCostNum(output)} / 1M tokens`,
		isFree: false,
		input,
		output,
		cacheRead,
		cacheWrite,
	};
}

function appendDetailPane(selector: any) {
	const theme = getTheme();
	if (!theme) return;

	const selected = selector.filteredModels?.[selector.selectedIndex];
	if (!selected) return;

	const model = selected.model;
	const providerId = selected.provider;
	const apiProtocol = model.api || null;

	selector.listContainer.addChild(new Spacer(1));
	selector.listContainer.addChild(new Text(theme.fg("border", "  " + "─".repeat(50)), 0, 0));
	selector.listContainer.addChild(new Spacer(0));

	const fullName = model.name || model.id;
	selector.listContainer.addChild(
		new Text(
			`  ${theme.bold(theme.fg("accent", fullName))}` + theme.fg("muted", `  [${providerId}]`),
			0,
			0,
		),
	);

	const line1Parts: string[] = [];
	if (model.contextWindow) {
		line1Parts.push(theme.fg("muted", "Context ") + theme.fg("accent", formatContextWindow(model.contextWindow)));
	}
	if (model.maxTokens) {
		line1Parts.push(theme.fg("muted", "MaxOut ") + theme.fg("muted", formatMaxTokens(model.maxTokens)));
	}
	if (apiProtocol) {
		line1Parts.push(theme.fg("muted", "API ") + theme.fg("accent", formatProtocolShort(apiProtocol)));
	}
	if (model.input) {
		line1Parts.push(theme.fg("muted", "Input ") + theme.fg("muted", formatInputShort(model.input)));
	}
	if (model.reasoning) {
		line1Parts.push(theme.fg("warning", "⚡ reasoning"));
	}

	if (line1Parts.length > 0) {
		selector.listContainer.addChild(
			new Text(`  ${line1Parts.join(theme.fg("muted", "  ·  "))}`, 0, 0),
		);
	}

	const costInfo = formatCostWithUnits(model.cost);
	if (costInfo) {
		const costColor = costInfo.isFree ? "success" : "muted";
		let costLine = theme.fg("muted", "Cost ") + theme.fg(costColor, costInfo.label);

		if (model.cost?.cacheRead) {
			costLine += theme.fg("muted", "  ·  cache read ") + theme.fg("muted", `$${formatCostNum(model.cost.cacheRead)} / 1M tokens`);
		}
		if (model.cost?.cacheWrite) {
			costLine += theme.fg("muted", "  ·  cache write ") + theme.fg("muted", `$${formatCostNum(model.cost.cacheWrite)} / 1M tokens`);
		}

		selector.listContainer.addChild(new Text(`  ${costLine}`, 0, 0));
	}

	if (model.baseUrl) {
		selector.listContainer.addChild(new Text(theme.fg("muted", "  BaseURL ") + theme.fg("muted", model.baseUrl), 0, 0));
	}

	const keyInfo = resolveApiKeyDisplay(selector, { ...model, provider: providerId, id: model.id });
	if (keyInfo) {
		let keyLine: string | null;
		switch (keyInfo.state) {
			case "loading":
				keyLine = theme.fg("muted", "  APIKey  ") + theme.fg("muted", "…");
				break;
			case "ok":
				keyLine =
					theme.fg("muted", "  APIKey  ") +
					theme.fg("accent", keyInfo.masked) +
					theme.fg("muted", `  (${keyInfo.len} chars)`);
				break;
			case "none":
				keyLine = theme.fg("muted", "  APIKey  ") + theme.fg("warning", "not configured");
				break;
			case "error":
				keyLine = theme.fg("muted", "  APIKey  ") + theme.fg("error", keyInfo.error);
				break;
			default:
				keyLine = null;
		}

		if (keyLine) {
			selector.listContainer.addChild(new Text(keyLine, 0, 0));
		}
	}
}

export function installModelSelectorCostUnitsPatches(ModelSelectorComponent: any) {
	const proto = ModelSelectorComponent.prototype;
	uninstallModelSelectorCostUnitsPatches(ModelSelectorComponent);

	const originalUpdateList = proto.updateList;
	const patchedUpdateList = function enhancedUpdateList() {
		originalUpdateList.call(this);
		try {
			appendDetailPane(this);
		} catch {
			// enhancement must not break model selector
		}
	};

	proto.updateList = patchedUpdateList;
	proto[UPDATE_LIST_PATCH] = {
		original: originalUpdateList,
		patched: patchedUpdateList,
	};

	return () => uninstallModelSelectorCostUnitsPatches(ModelSelectorComponent);
}

function uninstallModelSelectorCostUnitsPatches(ModelSelectorComponent: any) {
	const proto = ModelSelectorComponent.prototype;
	const patch = proto[UPDATE_LIST_PATCH];
	if (!patch) return;
	if (proto.updateList === patch.patched) {
		proto.updateList = patch.original;
	}
	delete proto[UPDATE_LIST_PATCH];
}

function getHostDistDir() {
	return dirname(realpathSync(process.argv[1]));
}

function getHostModuleUrl(relativePath: string) {
	return pathToFileURL(resolve(getHostDistDir(), relativePath)).href;
}

export default async function modelSelectorCostUnitsExtension(pi: ExtensionAPI) {
	const [{ ModelSelectorComponent }] = await Promise.all([
		import(getHostModuleUrl("modes/interactive/components/model-selector.js")),
	]);

	const unpatch = installModelSelectorCostUnitsPatches(ModelSelectorComponent);
	pi.on("session_shutdown", unpatch);
}

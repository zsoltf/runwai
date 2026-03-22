import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const silent = () => {};
console.log = silent;
console.warn = silent;
console.debug = silent;
console.error = silent;

function output(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function resolveGeminiPaths() {
  const geminiBinary =
    [
      process.env.GEMINI_CLI_PATH,
      "/opt/homebrew/bin/gemini",
      "/usr/local/bin/gemini",
      (() => {
        try {
          return execFileSync("/usr/bin/env", ["which", "gemini"], {
            encoding: "utf8",
          }).trim();
        } catch {
          return "";
        }
      })(),
    ].find((candidate) => candidate && fs.existsSync(candidate)) ?? "";

  if (!geminiBinary) {
    throw new Error("Gemini CLI is not installed or not on PATH.");
  }

  const geminiEntry = fs.realpathSync(geminiBinary);
  const distDir = path.dirname(geminiEntry);
  const packageDir = path.dirname(distDir);
  const coreDir = path.join(packageDir, "node_modules", "@google", "gemini-cli-core");

  return {
    settingsURL: pathToFileURL(path.join(packageDir, "dist", "src", "config", "settings.js")).href,
    contentGeneratorURL: pathToFileURL(path.join(coreDir, "dist", "src", "core", "contentGenerator.js")).href,
    oauthURL: pathToFileURL(path.join(coreDir, "dist", "src", "code_assist", "oauth2.js")).href,
    setupURL: pathToFileURL(path.join(coreDir, "dist", "src", "code_assist", "setup.js")).href,
    serverURL: pathToFileURL(path.join(coreDir, "dist", "src", "code_assist", "server.js")).href,
  };
}

function pickQuotaBucket(buckets) {
  const candidates = [
    "gemini-3.1-pro-preview",
    "gemini-3-pro-preview",
    "gemini-2.5-pro",
  ];

  for (const modelId of candidates) {
    const match = buckets.find((bucket) => bucket.modelId === modelId);
    if (match) {
      return match;
    }
  }

  return (
    buckets.find((bucket) => bucket.modelId?.includes("3.1-pro")) ??
    buckets.find((bucket) => bucket.modelId?.includes("3-pro")) ??
    buckets.find((bucket) => bucket.modelId?.includes("pro")) ??
    null
  );
}

try {
  const paths = resolveGeminiPaths();
  const [{ loadSettings }, { AuthType }, { getOauthClient }, { setupUser }, { CodeAssistServer }] =
    await Promise.all([
      import(paths.settingsURL),
      import(paths.contentGeneratorURL),
      import(paths.oauthURL),
      import(paths.setupURL),
      import(paths.serverURL),
    ]);

  const settings = loadSettings(process.cwd());
  const selectedAuthType = settings.merged.security?.auth?.selectedType;

  if (
    selectedAuthType !== AuthType.LOGIN_WITH_GOOGLE &&
    selectedAuthType !== AuthType.COMPUTE_ADC
  ) {
    output({
      ok: false,
      error: `Unsupported Gemini auth type: ${selectedAuthType ?? "unknown"}`,
    });
    process.exit(0);
  }

  const configStub = {
    getProxy() {
      return (
        process.env.HTTPS_PROXY ||
        process.env.https_proxy ||
        process.env.HTTP_PROXY ||
        process.env.http_proxy
      );
    },
    isBrowserLaunchSuppressed() {
      return true;
    },
    getAcpMode() {
      return false;
    },
  };

  const client = await getOauthClient(selectedAuthType, configStub);
  const userData = await setupUser(client, undefined, { headers: {} });
  const server = new CodeAssistServer(
    client,
    userData.projectId,
    { headers: {} },
    "runwai",
    userData.userTier,
    userData.userTierName,
    userData.paidTier
  );

  const quota = await server.retrieveUserQuota({ project: userData.projectId });
  const bucket = pickQuotaBucket(quota.buckets ?? []);

  output({
    ok: bucket !== null,
    tier: userData.userTierName,
    projectId: userData.projectId,
    bucketCount: quota.buckets?.length ?? 0,
    bucket: bucket
      ? {
          modelId: bucket.modelId,
          remainingFraction: bucket.remainingFraction,
          remainingAmount: bucket.remainingAmount,
          resetTime: bucket.resetTime,
        }
      : null,
    error: bucket ? null : "No Gemini quota bucket was available.",
  });
} catch (error) {
  output({
    ok: false,
    error: error instanceof Error ? error.message : String(error),
  });
}

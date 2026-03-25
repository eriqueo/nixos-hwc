/**
 * Heartwood MCP Server configuration.
 * All values come from environment variables (injected by systemd EnvironmentFile).
 */

export interface Config {
  jt: {
    grantKey: string;
    orgId: string;
    userId: string;
    apiUrl: string;
  };
  paperless?: {
    url: string;
    token: string;
  };
  firefly?: {
    url: string;
    token: string;
  };
  transport: "stdio" | "sse";
  sse: {
    host: string;
    port: number;
  };
  logLevel: "debug" | "info" | "warn" | "error";
}

export function loadConfig(): Config {
  const transport = (process.env.TRANSPORT ?? "stdio") as Config["transport"];

  return {
    jt: {
      grantKey: requireEnv("JT_GRANT_KEY"),
      orgId: process.env.JT_ORG_ID ?? "22Nm3uFevXMb",
      userId: process.env.JT_USER_ID ?? "22Nm3uFeRB7s",
      apiUrl: process.env.JT_API_URL ?? "https://api.jobtread.com/pave",
    },
    paperless: process.env.PAPERLESS_URL
      ? {
          url: process.env.PAPERLESS_URL,
          token: requireEnv("PAPERLESS_TOKEN"),
        }
      : undefined,
    firefly: process.env.FIREFLY_URL
      ? {
          url: process.env.FIREFLY_URL,
          token: requireEnv("FIREFLY_TOKEN"),
        }
      : undefined,
    transport,
    sse: {
      host: process.env.SSE_HOST ?? "127.0.0.1",
      port: parseInt(process.env.SSE_PORT ?? "6100", 10),
    },
    logLevel: (process.env.LOG_LEVEL ?? "info") as Config["logLevel"],
  };
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Required environment variable ${name} is not set`);
  }
  return value;
}

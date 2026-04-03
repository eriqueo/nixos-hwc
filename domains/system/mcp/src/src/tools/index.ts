/**
 * Tool aggregator — collects all tool modules into a single array.
 */

import type { ToolDef, ServerConfig } from "../types.js";
import { servicesTools } from "./services.js";
import { buildTools } from "./build.js";
import { monitoringTools } from "./monitoring.js";
import { configTools } from "./config.js";
import { secretsTools } from "./secrets.js";
import { storageTools } from "./storage.js";
import { networkTools } from "./network.js";
import { mailTools } from "./mail.js";
import { mediaTools } from "./media.js";

export function allTools(config: ServerConfig): ToolDef[] {
  return [
    ...servicesTools(config.cacheTtl.runtime),
    ...buildTools(config.nixosConfigPath, config.cacheTtl.runtime),
    ...monitoringTools(config.workspace, config.cacheTtl.runtime),
    ...configTools(config.nixosConfigPath, config.cacheTtl.declarative),
    ...secretsTools(config.nixosConfigPath),
    ...storageTools(config.cacheTtl.runtime),
    ...networkTools(config.cacheTtl.runtime, config.nixosConfigPath),
    ...mailTools(),
    ...mediaTools(),
  ];
}

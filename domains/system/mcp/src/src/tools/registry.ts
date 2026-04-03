/**
 * Tool registry — maps tool names to their definitions.
 * Mirrors the heartwood-mcp pattern.
 */

import type { ToolDef } from "../types.js";

export class ToolRegistry {
  private tools = new Map<string, ToolDef>();

  register(tools: ToolDef[]): void {
    for (const tool of tools) {
      if (this.tools.has(tool.name)) {
        throw new Error(`Duplicate tool name: ${tool.name}`);
      }
      this.tools.set(tool.name, tool);
    }
  }

  get(name: string): ToolDef | undefined {
    return this.tools.get(name);
  }

  getAll(): ToolDef[] {
    return Array.from(this.tools.values());
  }

  count(): number {
    return this.tools.size;
  }

  names(): string[] {
    return Array.from(this.tools.keys());
  }
}

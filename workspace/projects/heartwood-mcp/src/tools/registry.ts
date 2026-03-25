/**
 * Tool registry — defines the ToolDef interface and manages tool registration.
 */

import type { ToolResult } from "../pave/index.js";

/** JSON Schema for tool input */
export interface JsonSchema {
  type: "object";
  properties: Record<string, unknown>;
  required: string[];
}

/** Tool definition — matches MCP tool format */
export interface ToolDef {
  name: string;
  description: string;
  inputSchema: JsonSchema;
  handler: (params: Record<string, unknown>) => Promise<ToolResult>;
}

/**
 * Tool registry — maps tool names to their definitions.
 */
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

/**
 * hwc_estimator_* tools — manage trade rates, templates, and catalog
 * for the Heartwood Estimate Assembler.
 *
 * Data lives in the hwc Postgres database. These tools provide
 * read/write access and trigger exports + builds.
 */

import { execFile } from "node:child_process";
import type { ToolDef, ToolResult } from "../types.js";
import { mcpError, catchError } from "../errors.js";
import { psqlJson, psqlExec } from "../executors/psql.js";
import { log } from "../log.js";

// ── Helpers ────────────────────────────────────────────────────────────────

/** Run a script via python3 and return stdout. */
function runScript(
  scriptPath: string,
  args: string[] = [],
  timeout = 30000,
): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    execFile(
      "python3",
      [scriptPath, ...args],
      { timeout, maxBuffer: 1024 * 512 },
      (error, stdout, stderr) => {
        const exitCode = error && "code" in error ? (error.code as number) : 0;
        resolve({
          exitCode: typeof exitCode === "number" ? exitCode : 1,
          stdout: stdout.toString(),
          stderr: stderr.toString(),
        });
      },
    );
  });
}

// ── Tool definitions ───────────────────────────────────────────────────────

export function estimatorTools(nixosConfigPath: string): ToolDef[] {
  const dbDir = `${nixosConfigPath}/domains/business/databases`;

  return [
    // ── Trade Rates ──────────────────────────────────────────────────────

    {
      name: "hwc_estimator_rates",
      description:
        "List all trade rates from the hwc database. Shows wage, burden, markup, " +
        "computed cost (wage*burden), and computed price (cost*markup) for each trade.",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
        try {
          const rows = await psqlJson(
            "SELECT trade, base_wage, burden_factor, markup_factor, unit_cost, unit_price FROM trade_rates ORDER BY trade",
          );
          return {
            status: "ok",
            message: `${rows.length} trade rates`,
            data: rows,
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to query trade rates", err);
        }
      },
    },

    {
      name: "hwc_estimator_update_rate",
      description:
        "Update a trade rate in the hwc database. Changes base_wage, burden_factor, " +
        "and/or markup_factor for a trade. unit_cost and unit_price are auto-computed. " +
        "Run hwc_estimator_export after updating to propagate changes.",
      inputSchema: {
        type: "object",
        properties: {
          trade: {
            type: "string",
            description: "Trade name (e.g. 'demo', 'tile', 'plumbing')",
          },
          base_wage: { type: "number", description: "New base wage (optional)" },
          burden_factor: { type: "number", description: "New burden factor (optional)" },
          markup_factor: { type: "number", description: "New markup factor (optional)" },
        },
        required: ["trade"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const trade = args.trade as string;

          // Validate trade exists
          const existing = await psqlJson(
            `SELECT trade FROM trade_rates WHERE trade = '${trade.replace(/'/g, "''")}'`,
          );
          if (existing.length === 0) {
            return mcpError({
              type: "NOT_FOUND",
              message: `Trade '${trade}' not found`,
              suggestion: "Use hwc_estimator_rates to list valid trades",
            });
          }

          // Build SET clause from provided fields
          const sets: string[] = [];
          if (args.base_wage !== undefined)
            sets.push(`base_wage = ${Number(args.base_wage)}`);
          if (args.burden_factor !== undefined)
            sets.push(`burden_factor = ${Number(args.burden_factor)}`);
          if (args.markup_factor !== undefined)
            sets.push(`markup_factor = ${Number(args.markup_factor)}`);

          if (sets.length === 0) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: "No fields to update",
              suggestion: "Provide at least one of: base_wage, burden_factor, markup_factor",
            });
          }

          sets.push("updated_at = now()");
          const sql = `UPDATE trade_rates SET ${sets.join(", ")} WHERE trade = '${trade.replace(/'/g, "''")}'`;
          await psqlExec(sql);

          // Return updated row
          const updated = await psqlJson(
            `SELECT trade, base_wage, burden_factor, markup_factor, unit_cost, unit_price FROM trade_rates WHERE trade = '${trade.replace(/'/g, "''")}'`,
          );

          return {
            status: "ok",
            message: `Updated trade '${trade}'. Run hwc_estimator_export to propagate.`,
            data: updated[0],
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to update trade rate", err);
        }
      },
    },

    // ── Templates ────────────────────────────────────────────────────────

    {
      name: "hwc_estimator_templates",
      description:
        "List estimate templates. Optionally filter by project_type (bathroom, deck). " +
        "Templates are pre-configured state snapshots for common job configurations.",
      inputSchema: {
        type: "object",
        properties: {
          project_type: {
            type: "string",
            description: "Filter by project type (e.g. 'bathroom', 'deck'). Omit for all.",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const pt = args.project_type as string | undefined;
          const where = pt
            ? `WHERE is_active = true AND project_type = '${pt.replace(/'/g, "''")}'`
            : "WHERE is_active = true";
          const rows = await psqlJson(
            `SELECT id, name, project_type, description, created_at::text, updated_at::text FROM estimate_templates ${where} ORDER BY project_type, name`,
          );
          return {
            status: "ok",
            message: `${rows.length} templates`,
            data: rows,
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to query templates", err);
        }
      },
    },

    {
      name: "hwc_estimator_save_template",
      description:
        "Save or update an estimate template in the database. " +
        "The state should be a JSON object with all assembler state keys. " +
        "Run hwc_estimator_export after to update the app.",
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string", description: "Template name (unique)" },
          project_type: {
            type: "string",
            enum: ["bathroom", "deck"],
            description: "Project type",
          },
          description: { type: "string", description: "Short description" },
          state: {
            type: "object",
            description: "Full state snapshot (measurements, toggles, allowances)",
          },
        },
        required: ["name", "project_type", "state"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const name = (args.name as string).replace(/'/g, "''");
          const pt = (args.project_type as string).replace(/'/g, "''");
          const desc = ((args.description as string) || "").replace(/'/g, "''");
          const stateJson = JSON.stringify(args.state).replace(/'/g, "''");

          const sql =
            `INSERT INTO estimate_templates (name, project_type, description, state) ` +
            `VALUES ('${name}', '${pt}', '${desc}', '${stateJson}'::jsonb) ` +
            `ON CONFLICT (name) DO UPDATE SET ` +
            `state = EXCLUDED.state, description = EXCLUDED.description, ` +
            `project_type = EXCLUDED.project_type, updated_at = now()`;

          await psqlExec(sql);
          return {
            status: "ok",
            message: `Template '${args.name}' saved. Run hwc_estimator_export to update app.`,
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to save template", err);
        }
      },
    },

    {
      name: "hwc_estimator_delete_template",
      description: "Soft-delete an estimate template (sets is_active = false).",
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string", description: "Template name to delete" },
        },
        required: ["name"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const name = (args.name as string).replace(/'/g, "''");
          const result = await psqlExec(
            `UPDATE estimate_templates SET is_active = false, updated_at = now() WHERE name = '${name}'`,
          );
          if (result.rowCount === 0) {
            return mcpError({ type: "NOT_FOUND", message: `Template '${args.name}' not found` });
          }
          return {
            status: "ok",
            message: `Template '${args.name}' deleted. Run hwc_estimator_export to update app.`,
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to delete template", err);
        }
      },
    },

    // ── Catalog (Price Book) ────────────────────────────────────────────

    {
      name: "hwc_estimator_catalog",
      description:
        "Query the price book (catalog_items). Returns items with pricing and " +
        "JT metadata. No assembly logic — use hwc_estimator_rules for that. " +
        "Filter by item_type, trade, or search term.",
      inputSchema: {
        type: "object",
        properties: {
          item_type: {
            type: "string",
            enum: ["labor", "material", "allowance", "other"],
            description: "Filter by item type",
          },
          trade: {
            type: "string",
            description: "Filter by trade (e.g., 'demo', 'tile', 'plumbing')",
          },
          search: {
            type: "string",
            description: "Search display_name, canonical_name, or description (case-insensitive)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const conditions = ["is_active = true"];
          const it = args.item_type as string | undefined;
          const trade = args.trade as string | undefined;
          const search = args.search as string | undefined;

          if (it) conditions.push(`item_type = '${it.replace(/'/g, "''")}'`);
          if (trade) conditions.push(`trade = '${trade.replace(/'/g, "''")}'`);
          if (search) {
            const s = search.replace(/'/g, "''");
            conditions.push(
              `(display_name ILIKE '%${s}%' OR canonical_name ILIKE '%${s}%' OR description ILIKE '%${s}%')`,
            );
          }

          const rows = await psqlJson(
            `SELECT id, display_name, item_type, trade, unit_cost, unit_price, ` +
            `budget_group_path, vendor, description ` +
            `FROM catalog_items WHERE ${conditions.join(" AND ")} ` +
            `ORDER BY item_type, trade, display_name LIMIT 100`,
          );
          return {
            status: "ok",
            message: `${rows.length} catalog items (price book)`,
            data: rows,
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to query catalog", err);
        }
      },
    },

    // ── Assembly Rules ──────────────────────────────────────────────────

    {
      name: "hwc_estimator_rules",
      description:
        "Query assembly rules joined to catalog items. Shows how items are used " +
        "in automated estimates per project type. Filter by project_type, trade, " +
        "or search term.",
      inputSchema: {
        type: "object",
        properties: {
          project_type: {
            type: "string",
            description: "Filter by project type (bathroom, deck, kitchen, general)",
          },
          trade: {
            type: "string",
            description: "Filter by trade",
          },
          search: {
            type: "string",
            description: "Search item name or description (case-insensitive)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const conditions = ["ar.is_active = true", "ci.is_active = true"];
          const pt = args.project_type as string | undefined;
          const trade = args.trade as string | undefined;
          const search = args.search as string | undefined;

          if (pt) conditions.push(`ar.project_type = '${pt.replace(/'/g, "''")}'`);
          if (trade) conditions.push(`ci.trade = '${trade.replace(/'/g, "''")}'`);
          if (search) {
            const s = search.replace(/'/g, "''");
            conditions.push(`(ci.display_name ILIKE '%${s}%' OR ar.description ILIKE '%${s}%')`);
          }

          const rows = await psqlJson(
            `SELECT ar.id AS rule_id, ci.display_name, ci.item_type, ci.trade, ` +
            `COALESCE(ar.unit_cost_override, ci.unit_cost) AS unit_cost, ` +
            `COALESCE(ar.unit_price_override, ci.unit_price) AS unit_price, ` +
            `ar.project_type, ar.condition_trigger, ar.qty_formula, ` +
            `ar.default_qty, ar.production_rate, ar.waste_factor, ar.sort_order, ` +
            `ar.budget_group_path ` +
            `FROM assembly_rules ar ` +
            `JOIN catalog_items ci ON ar.catalog_item_id = ci.id ` +
            `WHERE ${conditions.join(" AND ")} ` +
            `ORDER BY ar.sort_order LIMIT 100`,
          );
          return {
            status: "ok",
            message: `${rows.length} assembly rules`,
            data: rows,
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Failed to query assembly rules", err);
        }
      },
    },

    // ── Export & Build ────────────────────────────────────────────────────

    {
      name: "hwc_estimator_export",
      description:
        "Export estimator data from the hwc database to JSON files " +
        "(tradeRates.json, catalog_export.json, templates.json). " +
        "Also exports calculator JSON. Run this after changing rates, " +
        "templates, or catalog items.",
      inputSchema: {
        type: "object",
        properties: {
          include_calculator: {
            type: "boolean",
            description: "Also export calculator JSON (default: true)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const results: string[] = [];

          // Export estimator data
          const estResult = await runScript(`${dbDir}/export_estimator_data.py`);
          if (estResult.exitCode !== 0) {
            return mcpError({
              type: "COMMAND_FAILED",
              message: "Estimator export failed",
              error: estResult.stderr || estResult.stdout,
            });
          }
          results.push(estResult.stdout.trim());

          // Export calculator JSON
          const inclCalc = args.include_calculator !== false;
          if (inclCalc) {
            const calcResult = await runScript(`${dbDir}/export_calculator_json.py`);
            if (calcResult.exitCode !== 0) {
              results.push(`Calculator export failed: ${calcResult.stderr}`);
            } else {
              results.push(calcResult.stdout.trim());
            }
          }

          return {
            status: "ok",
            message: "Export complete. Rebuild apps to pick up changes.",
            data: { output: results.join("\n\n") },
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Export failed", err);
        }
      },
    },

    {
      name: "hwc_estimator_build",
      description:
        "Rebuild the estimator app from source. Runs the Nix-managed build " +
        "service which compiles the React app and deploys via atomic symlink. " +
        "Run hwc_estimator_export first if data has changed.",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
        try {
          log.info("Starting estimator build");

          // Clear build hash to force rebuild
          const clearResult = await new Promise<{ exitCode: number; stdout: string; stderr: string }>((resolve) => {
            execFile(
              "sudo",
              ["rm", "-f", "/var/lib/estimator-build/.last-build-hash"],
              { timeout: 5000 },
              (error, stdout, stderr) => {
                resolve({
                  exitCode: error && "code" in error ? (error.code as number) : 0,
                  stdout: stdout.toString(),
                  stderr: stderr.toString(),
                });
              },
            );
          });

          if (clearResult.exitCode !== 0) {
            log.warn("Failed to clear build hash", { stderr: clearResult.stderr });
          }

          // Start the build service
          const buildResult = await new Promise<{ exitCode: number; stdout: string; stderr: string }>((resolve) => {
            execFile(
              "sudo",
              ["systemctl", "start", "estimator-build"],
              { timeout: 120000 },
              (error, stdout, stderr) => {
                const exitCode = error && "code" in error ? (error.code as number) : 0;
                resolve({
                  exitCode: typeof exitCode === "number" ? exitCode : 1,
                  stdout: stdout.toString(),
                  stderr: stderr.toString(),
                });
              },
            );
          });

          if (buildResult.exitCode !== 0) {
            return mcpError({
              type: "COMMAND_FAILED",
              message: "Estimator build failed",
              error: buildResult.stderr,
              suggestion: "Check: sudo journalctl -u estimator-build --no-pager -n 20",
            });
          }

          return {
            status: "ok",
            message: "Estimator built and deployed successfully",
          };
        } catch (err) {
          return catchError("COMMAND_FAILED", "Build failed", err);
        }
      },
    },
  ];
}

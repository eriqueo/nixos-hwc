/**
 * hwc_estimator — consolidated estimator tool (catalog, rates, rules, templates, build, export, save_template, delete_template, update_rate).
 */

import { execFile } from "node:child_process";
import type { ToolDef, ToolResult } from "../types.js";
import { mcpError, catchError } from "../errors.js";
import { psqlJson, psqlExec } from "../executors/psql.js";
import { log } from "../log.js";

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

export function estimatorTools(nixosConfigPath: string): ToolDef[] {
  const dbDir = `${nixosConfigPath}/domains/business/databases`;

  return [
    {
      name: "hwc_estimator",
      description:
        "Estimator management. Actions: catalog, rates, rules, templates, build, export, save_template, delete_template, update_rate.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["catalog", "rates", "rules", "templates", "build", "export", "save_template", "delete_template", "update_rate"],
            description: "Action to perform",
          },
          // [catalog] params
          item_type: {
            type: "string",
            enum: ["labor", "material", "allowance", "other"],
            description: "[catalog/rules] Filter by item type",
          },
          trade: {
            type: "string",
            description: "[catalog/rules/update_rate] Trade name (e.g. 'demo', 'tile', 'plumbing')",
          },
          search: {
            type: "string",
            description: "[catalog/rules] Search display_name, canonical_name, or description (case-insensitive)",
          },
          // [templates] params
          project_type: {
            type: "string",
            description: "[templates/rules/save_template] Filter/set project type (e.g. 'bathroom', 'deck')",
          },
          // [update_rate] params
          base_wage: { type: "number", description: "[update_rate] New base wage" },
          burden_factor: { type: "number", description: "[update_rate] New burden factor" },
          markup_factor: { type: "number", description: "[update_rate] New markup factor" },
          // [save_template] params
          name: { type: "string", description: "[save_template/delete_template] Template name (unique)" },
          description: { type: "string", description: "[save_template] Short description" },
          state: {
            type: "object",
            description: "[save_template] Full state snapshot (measurements, toggles, allowances)",
          },
          // [export] params
          include_calculator: {
            type: "boolean",
            description: "[export] Also export calculator JSON (default: true)",
          },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── rates ────────────────────────────────────────────────
        if (action === "rates") {
          try {
            const rows = await psqlJson(
              "SELECT trade, base_wage, burden_factor, markup_factor, unit_cost, unit_price FROM trade_rates ORDER BY trade",
            );
            return { status: "ok", message: `${rows.length} trade rates`, data: rows };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to query trade rates", err);
          }
        }

        // ── update_rate ──────────────────────────────────────────
        if (action === "update_rate") {
          try {
            const trade = args.trade as string;
            if (!trade) return mcpError({ type: "VALIDATION_ERROR", message: "trade is required for action=update_rate" });

            const existing = await psqlJson(
              `SELECT trade FROM trade_rates WHERE trade = '${trade.replace(/'/g, "''")}'`,
            );
            if (existing.length === 0) {
              return mcpError({ type: "NOT_FOUND", message: `Trade '${trade}' not found`, suggestion: "Use hwc_estimator action=rates to list valid trades" });
            }

            const sets: string[] = [];
            if (args.base_wage !== undefined) sets.push(`base_wage = ${Number(args.base_wage)}`);
            if (args.burden_factor !== undefined) sets.push(`burden_factor = ${Number(args.burden_factor)}`);
            if (args.markup_factor !== undefined) sets.push(`markup_factor = ${Number(args.markup_factor)}`);

            if (sets.length === 0) {
              return mcpError({ type: "VALIDATION_ERROR", message: "No fields to update", suggestion: "Provide at least one of: base_wage, burden_factor, markup_factor" });
            }

            sets.push("updated_at = now()");
            const sql = `UPDATE trade_rates SET ${sets.join(", ")} WHERE trade = '${trade.replace(/'/g, "''")}'`;
            await psqlExec(sql);

            const updated = await psqlJson(
              `SELECT trade, base_wage, burden_factor, markup_factor, unit_cost, unit_price FROM trade_rates WHERE trade = '${trade.replace(/'/g, "''")}'`,
            );

            return {
              status: "ok",
              message: `Updated trade '${trade}'. Run hwc_estimator action=export to propagate.`,
              data: updated[0],
            };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to update trade rate", err);
          }
        }

        // ── templates ────────────────────────────────────────────
        if (action === "templates") {
          try {
            const pt = args.project_type as string | undefined;
            const where = pt
              ? `WHERE is_active = true AND project_type = '${pt.replace(/'/g, "''")}'`
              : "WHERE is_active = true";
            const rows = await psqlJson(
              `SELECT id, name, project_type, description, created_at::text, updated_at::text FROM estimate_templates ${where} ORDER BY project_type, name`,
            );
            return { status: "ok", message: `${rows.length} templates`, data: rows };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to query templates", err);
          }
        }

        // ── save_template ────────────────────────────────────────
        if (action === "save_template") {
          try {
            const name = args.name as string;
            const pt = args.project_type as string;
            if (!name || !pt || !args.state) {
              return mcpError({ type: "VALIDATION_ERROR", message: "name, project_type, and state are required for action=save_template" });
            }
            const escapedName = name.replace(/'/g, "''");
            const escapedPt = pt.replace(/'/g, "''");
            const desc = ((args.description as string) || "").replace(/'/g, "''");
            const stateJson = JSON.stringify(args.state).replace(/'/g, "''");

            const sql =
              `INSERT INTO estimate_templates (name, project_type, description, state) ` +
              `VALUES ('${escapedName}', '${escapedPt}', '${desc}', '${stateJson}'::jsonb) ` +
              `ON CONFLICT (name) DO UPDATE SET ` +
              `state = EXCLUDED.state, description = EXCLUDED.description, ` +
              `project_type = EXCLUDED.project_type, updated_at = now()`;

            await psqlExec(sql);
            return {
              status: "ok",
              message: `Template '${name}' saved. Run hwc_estimator action=export to update app.`,
            };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to save template", err);
          }
        }

        // ── delete_template ──────────────────────────────────────
        if (action === "delete_template") {
          try {
            const name = args.name as string;
            if (!name) return mcpError({ type: "VALIDATION_ERROR", message: "name is required for action=delete_template" });
            const escapedName = name.replace(/'/g, "''");
            const result = await psqlExec(
              `UPDATE estimate_templates SET is_active = false, updated_at = now() WHERE name = '${escapedName}'`,
            );
            if (result.rowCount === 0) {
              return mcpError({ type: "NOT_FOUND", message: `Template '${name}' not found` });
            }
            return {
              status: "ok",
              message: `Template '${name}' deleted. Run hwc_estimator action=export to update app.`,
            };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to delete template", err);
          }
        }

        // ── catalog ──────────────────────────────────────────────
        if (action === "catalog") {
          try {
            const conditions = ["is_active = true"];
            const it = args.item_type as string | undefined;
            const trade = args.trade as string | undefined;
            const search = args.search as string | undefined;

            if (it) conditions.push(`item_type = '${it.replace(/'/g, "''")}'`);
            if (trade) conditions.push(`trade = '${trade.replace(/'/g, "''")}'`);
            if (search) {
              const s = search.replace(/'/g, "''");
              conditions.push(`(display_name ILIKE '%${s}%' OR canonical_name ILIKE '%${s}%' OR description ILIKE '%${s}%')`);
            }

            const rows = await psqlJson(
              `SELECT id, display_name, item_type, trade, unit_cost, unit_price, ` +
              `budget_group_path, vendor, description ` +
              `FROM catalog_items WHERE ${conditions.join(" AND ")} ` +
              `ORDER BY item_type, trade, display_name LIMIT 100`,
            );
            return { status: "ok", message: `${rows.length} catalog items (price book)`, data: rows };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to query catalog", err);
          }
        }

        // ── rules ────────────────────────────────────────────────
        if (action === "rules") {
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
            return { status: "ok", message: `${rows.length} assembly rules`, data: rows };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to query assembly rules", err);
          }
        }

        // ── export ───────────────────────────────────────────────
        if (action === "export") {
          try {
            const results: string[] = [];

            const estResult = await runScript(`${dbDir}/export_estimator_data.py`);
            if (estResult.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "Estimator export failed", error: estResult.stderr || estResult.stdout });
            }
            results.push(estResult.stdout.trim());

            const inclCalc = args.include_calculator !== false;
            if (inclCalc) {
              const calcResult = await runScript(`${dbDir}/export_calculator_json.py`);
              if (calcResult.exitCode !== 0) {
                results.push(`Calculator export failed: ${calcResult.stderr}`);
              } else {
                results.push(calcResult.stdout.trim());
              }
            }

            return { status: "ok", message: "Export complete. Rebuild apps to pick up changes.", data: { output: results.join("\n\n") } };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Export failed", err);
          }
        }

        // ── build ────────────────────────────────────────────────
        if (action === "build") {
          try {
            log.info("Starting estimator build");

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
              return mcpError({ type: "COMMAND_FAILED", message: "Estimator build failed", error: buildResult.stderr, suggestion: "Check: sudo journalctl -u estimator-build --no-pager -n 20" });
            }

            return { status: "ok", message: "Estimator built and deployed successfully" };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Build failed", err);
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
      },
    },
  ];
}

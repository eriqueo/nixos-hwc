/**
 * hwc_build_* tools — git status, flake metadata, build operations.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { catchError } from "../errors.js";
import { safeExec } from "../executors/shell.js";
import { TtlCache } from "../cache.js";

const cache = new TtlCache();

export function buildTools(nixosConfigPath: string, runtimeTtl: number): ToolDef[] {
  return [
    {
      name: "hwc_build_git_status",
      description:
        "Get git status of the nixos-hwc repo — current branch, uncommitted changes, unpushed commits, " +
        "and recent commit history. Use before builds to check for uncommitted work.",
      inputSchema: {
        type: "object",
        properties: {
          log_count: {
            type: "integer",
            default: 10,
            description: "Number of recent commits to include",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const logCount = Math.min((args.log_count as number) || 10, 50);
          const gitDir = nixosConfigPath;

          // Run git queries in parallel
          const [branchResult, statusResult, logResult, unpushedResult] =
            await Promise.all([
              safeExec("git", ["-C", gitDir, "rev-parse", "--abbrev-ref", "HEAD"]),
              safeExec("git", ["-C", gitDir, "status", "--porcelain"]),
              safeExec("git", ["-C", gitDir, "log", "--oneline", `-n${logCount}`]),
              safeExec("git", ["-C", gitDir, "rev-list", "HEAD...@{u}"], { timeout: 5000 }).catch(
                () => ({ exitCode: 1, stdout: "", stderr: "no upstream" })
              ),
            ]);

          const branch = branchResult.stdout.trim();
          const uncommitted = statusResult.stdout
            .split("\n")
            .filter(Boolean)
            .map((line) => ({
              status: line.slice(0, 2).trim(),
              file: line.slice(3),
            }));
          const recentCommits = logResult.stdout
            .split("\n")
            .filter(Boolean)
            .map((line) => {
              const spaceIdx = line.indexOf(" ");
              return {
                hash: line.slice(0, spaceIdx),
                message: line.slice(spaceIdx + 1),
              };
            });
          const unpushedCount = unpushedResult.stdout
            .split("\n")
            .filter(Boolean).length;

          return {
            status: "ok",
            message: `Branch: ${branch}, ${uncommitted.length} uncommitted, ${unpushedCount} unpushed`,
            data: {
              branch,
              clean: uncommitted.length === 0,
              uncommitted,
              unpushedCount,
              recentCommits,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to query git status", err, "Is the nixos-hwc repo accessible?");
        }
      },
    },
  ];
}

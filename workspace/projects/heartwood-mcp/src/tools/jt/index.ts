/**
 * JT tools index — exports all 63 JobTread tools.
 */

import type { PaveClient } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { accountTools } from "./accounts.js";
import { locationTools } from "./locations.js";
import { jobTools } from "./jobs.js";
import { budgetTools } from "./budget.js";
import { documentTools } from "./documents.js";
import { paymentTools } from "./payments.js";
import { taskTools } from "./tasks.js";
import { timeEntryTools } from "./time-entries.js";
import { dailyLogTools } from "./daily-logs.js";
import { fileTools } from "./files.js";
import { jobFolderTools } from "./job-folders.js";
import { commentTools } from "./comments.js";
import { dashboardTools } from "./dashboards.js";
import { customFieldTools } from "./custom-fields.js";
import { orgUserTools } from "./org-users.js";

/**
 * Register all 63 JT tools with the PAVE client.
 */
export function allJtTools(pave: PaveClient): ToolDef[] {
  return [
    ...accountTools(pave),     // 6 tools
    ...locationTools(pave),    // 2 tools
    ...jobTools(pave),         // 5 tools
    ...budgetTools(pave),      // 9 tools
    ...documentTools(pave),    // 5 tools
    ...paymentTools(pave),     // 2 tools
    ...taskTools(pave),        // 7 tools
    ...timeEntryTools(pave),   // 4 tools
    ...dailyLogTools(pave),    // 4 tools
    ...fileTools(pave),        // 7 tools
    ...jobFolderTools(pave),   // 1 tool
    ...commentTools(pave),     // 3 tools
    ...dashboardTools(pave),   // 3 tools
    ...customFieldTools(pave), // 2 tools
    ...orgUserTools(pave),     // 3 tools
  ];
  // Total: 63 tools
}

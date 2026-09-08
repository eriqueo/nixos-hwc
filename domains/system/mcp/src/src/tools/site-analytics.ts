/** Read-only, bounded Umami aggregates for the configured business website. */
import type { ToolDef, ExecResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError } from "../errors.js";

type Query = (sql: string, db: string, options: {timeout:number}) => Promise<ExecResult>;

export function siteAnalyticsTools(websiteId: string, database: string, query: Query): ToolDef[] {
  return [{name:"hwc_site_analytics", description:"Business website visits and page views for the last seven days, plus top pages. Read-only Umami aggregates.",
    inputSchema:{type:"object",properties:{}},
    handler: async () => {
      if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(websiteId) || !/^[a-z_][a-z0-9_]*$/i.test(database))
        return mcpError({type:"UNAVAILABLE",message:"Business analytics is not configured."});
      // Fixed SQL, no caller-supplied filters. Four-second deadline, fourteen-day
      // scan for comparison, five aggregate page rows. No personal/session data leaves SQL.
      const sql = `BEGIN READ ONLY; SET LOCAL statement_timeout='3500ms';
        WITH events AS (
          SELECT e.visit_id, e.url_path, e.created_at
          FROM website_event e JOIN website w USING (website_id)
          WHERE e.website_id='${websiteId}'::uuid AND w.deleted_at IS NULL
            AND e.event_type=1 AND e.created_at >= now()-interval '14 days'
            AND (w.reset_at IS NULL OR e.created_at >= w.reset_at)
        ), current AS (SELECT * FROM events WHERE created_at >= now()-interval '7 days'),
        pages AS (SELECT url_path, count(*) AS views FROM current GROUP BY url_path ORDER BY views DESC,url_path LIMIT 5)
        SELECT json_build_object(
          'visits',(SELECT count(DISTINCT visit_id) FROM current),
          'pageviews',(SELECT count(*) FROM current),
          'previous_visits',(SELECT count(DISTINCT visit_id) FROM events WHERE created_at < now()-interval '7 days'),
          'pages',(SELECT coalesce(json_agg(pages),'[]'::json) FROM pages)); COMMIT;`;
      try {
        const result = await query(sql,database,{timeout:4000});
        if (result.exitCode !== 0) throw Error("query failed");
        // psql -q suppresses transaction tags; tolerate existing executor's command tags.
        const raw = result.stdout.split("\n").find(line => line.trim().startsWith("{"));
        if (!raw) throw Error("missing result");
        const data = JSON.parse(raw);
        if (![data.visits,data.pageviews,data.previous_visits].every(n=>Number.isInteger(n)&&n>=0) || !Array.isArray(data.pages))
          throw Error("invalid aggregate");
        return {status:"ok", message:"Website activity", view:contract("text","Website activity",{
          greeting:`${data.visits} visits · ${data.pageviews} page views`,
          summary:`Last 7 days · previous 7 days: ${data.previous_visits} visits`,
          highlights:data.pages.map((p:{url_path:string,views:number})=>`${p.url_path} — ${p.views} views`),
        },{source:"umami",window_days:7})};
      } catch { return mcpError({type:"COMMAND_FAILED",message:"Cannot read website analytics. Open Umami or refresh."}); }
    }}];
}

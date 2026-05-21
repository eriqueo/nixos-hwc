import { getDaySummaries, getCategorySummary } from '../db/queries.js';
import { loadConfig } from '../config/index.js';
import { dateRange } from '../lib/time.js';
import { generateInvoiceAsync } from '../pdf/invoice.js';

export async function cmdExport(opts: { from: string; to: string }): Promise<void> {
  const config = loadConfig();
  const range = dateRange(opts.from, opts.to);
  const days = getDaySummaries(range.from, range.to);
  const categories = getCategorySummary(range.from, range.to);
  const totalMinutes = categories.reduce((s, c) => s + c.total_minutes, 0);

  if (days.length === 0) {
    console.error(`No sessions found between ${opts.from} and ${opts.to}`);
    process.exit(1);
  }

  const outPath = await generateInvoiceAsync({
    config,
    from: opts.from,
    to: opts.to,
    days,
    categories,
    totalMinutes,
  });

  console.log(outPath);
}

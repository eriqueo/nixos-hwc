import { startSession } from '../db/queries.js';
import { loadConfig } from '../config/index.js';

export function cmdIn(category?: string): void {
  const config = loadConfig();
  const cat = category || config.default_category || undefined;
  try {
    const session = startSession(cat);
    const label = session.category ? ` [${session.category}]` : '';
    console.log(`Clocked in${label} at ${new Date(session.start_at).toLocaleTimeString()}`);
  } catch (e: any) {
    console.error(e.message);
    process.exit(1);
  }
}

#!/usr/bin/env node
import { Command } from 'commander';
import { cmdIn } from './in.js';
import { cmdOut } from './out.js';
import { cmdToggle } from './toggle.js';
import { cmdStatus } from './status.js';
import { cmdLog } from './log.js';
import { cmdAmend } from './amend.js';
import { cmdExport } from './export.js';
import { cmdStaleCheck } from './stale-check.js';
import { cmdPomodoroCheck } from './pomodoro-check.js';
import { cmdCalendarRebuild } from './calendar-rebuild.js';
import { cmdDoctor } from './doctor.js';
import { cmdSnooze } from './snooze.js';

const program = new Command();

program
  .name('dt')
  .description('DataX time tracker')
  .version('1.0.0');

program
  .command('in')
  .description('Clock in')
  .argument('[category]', 'category slug')
  .action(cmdIn);

program
  .command('out')
  .description('Clock out')
  .option('-n, --notes <notes>', 'what you worked on')
  .option('-c, --category <cat>', 'override category')
  .action(cmdOut);

program
  .command('toggle')
  .description('Toggle clock in/out (for Waybar)')
  .argument('[category]', 'category for clock-in')
  .action(cmdToggle);

program
  .command('status')
  .description('Current status')
  .option('--waybar', 'JSON output for Waybar')
  .option('--json', 'JSON output')
  .action(cmdStatus);

program
  .command('log')
  .description('Show time log')
  .argument('[period]', 'today, yesterday, or YYYY-MM-DD', 'today')
  .action(cmdLog);

for (const [period, label, rangeName, description] of [
  ['week', 'Week', 'weekRange', 'Weekly summary'],
  ['month', 'Month', 'monthRange', 'Monthly summary'],
] as const) {
  program
    .command(period)
    .description(description)
    .option('-b, --back <n>', `${period}s back`, '0')
    .action(async (opts) => {
      const time = await import('../lib/time.js');
      const { getCategorySummary } = await import('../db/queries.js');
      const range = time[rangeName](parseInt(opts.back));
      const categories = getCategorySummary(range.from, range.to);
      const total = categories.reduce((sum, row) => sum + row.total_minutes, 0);
      console.log(`${label} ${opts.back === '0' ? '(current)' : `-${opts.back}`}:`);
      for (const row of categories) {
        console.log(`  ${row.category.padEnd(14)} ${time.formatDuration(row.total_minutes)}`);
      }
      console.log(`  ${'─'.repeat(22)}`);
      console.log(`  ${'TOTAL'.padEnd(14)} ${time.formatDuration(total)}`);
    });
}

program
  .command('amend')
  .description('Edit a session')
  .argument('<target>', '"last" or session ID')
  .option('--start <time>', 'new start (HH:MM or ISO)')
  .option('--end <time>', 'new end (HH:MM or ISO)')
  .option('-c, --category <cat>', 'new category')
  .option('-n, --notes <notes>', 'new notes')
  .action(cmdAmend);

program
  .command('export')
  .description('Generate PDF invoice')
  .requiredOption('--from <date>', 'start date (YYYY-MM-DD)')
  .requiredOption('--to <date>', 'end date (YYYY-MM-DD)')
  .action(cmdExport);

program
  .command('stale-check')
  .description('Check for stale sessions (systemd timer)')
  .action(cmdStaleCheck);

program
  .command('pomodoro-check')
  .description('Check pomodoro boundary on active session (systemd timer)')
  .action(cmdPomodoroCheck);

program
  .command('calendar-rebuild')
  .description('Rewrite every completed session as an .ics file under calendar_dir')
  .action(cmdCalendarRebuild);

program
  .command('doctor')
  .description('Verify config, DB, timers, calendar, and ABI')
  .action(cmdDoctor);

program
  .command('snooze')
  .description('Silence stale-session prompts for N minutes')
  .option('-m, --minutes <n>', 'minutes to snooze', '15')
  .action(cmdSnooze);

program
  .command('tui')
  .description('Open interactive TUI')
  .action(async () => {
    const { startTui } = await import('../tui/index.js');
    startTui();
  });

program.parse();

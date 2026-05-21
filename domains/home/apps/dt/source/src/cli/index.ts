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

program
  .command('week')
  .description('Weekly summary')
  .option('-b, --back <n>', 'weeks back', '0')
  .action((opts) => {
    import('../lib/time.js').then(({ weekRange, formatDuration }) => {
      import('../db/queries.js').then(({ getCategorySummary }) => {
        const range = weekRange(parseInt(opts.back));
        const cats = getCategorySummary(range.from, range.to);
        const total = cats.reduce((s, c) => s + c.total_minutes, 0);
        console.log(`Week ${opts.back === '0' ? '(current)' : `-${opts.back}`}:`);
        for (const c of cats) {
          console.log(`  ${c.category.padEnd(14)} ${formatDuration(c.total_minutes)}`);
        }
        console.log(`  ${'─'.repeat(22)}`);
        console.log(`  ${'TOTAL'.padEnd(14)} ${formatDuration(total)}`);
      });
    });
  });

program
  .command('month')
  .description('Monthly summary')
  .option('-b, --back <n>', 'months back', '0')
  .action((opts) => {
    import('../lib/time.js').then(({ monthRange, formatDuration }) => {
      import('../db/queries.js').then(({ getCategorySummary }) => {
        const range = monthRange(parseInt(opts.back));
        const cats = getCategorySummary(range.from, range.to);
        const total = cats.reduce((s, c) => s + c.total_minutes, 0);
        console.log(`Month ${opts.back === '0' ? '(current)' : `-${opts.back}`}:`);
        for (const c of cats) {
          console.log(`  ${c.category.padEnd(14)} ${formatDuration(c.total_minutes)}`);
        }
        console.log(`  ${'─'.repeat(22)}`);
        console.log(`  ${'TOTAL'.padEnd(14)} ${formatDuration(total)}`);
      });
    });
  });

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

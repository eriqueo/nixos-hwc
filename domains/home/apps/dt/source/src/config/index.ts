import fs from 'node:fs';
import path from 'node:path';
import TOML from '@iarna/toml';
import type { Config } from '../lib/types.js';

function configDir(): string {
  const xdg = process.env.XDG_CONFIG_HOME || path.join(process.env.HOME || '~', '.config');
  return path.join(xdg, 'dt');
}

export function configPath(): string {
  return path.join(configDir(), 'config.toml');
}

export function loadConfig(): Config {
  const p = configPath();
  if (!fs.existsSync(p)) {
    console.error(`Config not found: ${p}`);
    console.error(`Copy config.example.toml to ${p} and edit it.`);
    process.exit(1);
  }

  const raw = TOML.parse(fs.readFileSync(p, 'utf-8')) as Record<string, any>;

  return {
    name: raw.name ?? 'Eric O\'Keefe',
    rate: raw.rate ?? 40,
    max_session_hours: raw.max_session_hours ?? 10,
    waybar_poll_seconds: raw.waybar_poll_seconds ?? 30,
    default_category: raw.default_category ?? null,
    pomodoro_minutes: raw.pomodoro_minutes ?? 25,
    calendar_dir: raw.calendar_dir ?? null,
  };
}

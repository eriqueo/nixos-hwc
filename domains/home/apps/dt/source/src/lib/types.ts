export interface Session {
  id: number;
  start_at: string; // ISO 8601
  end_at: string | null;
  category: string | null;
  notes: string | null;
  pomodoros_notified: number;
}

export interface Category {
  id: number;
  slug: string;
  label: string;
  color: string;
}

export interface Config {
  name: string;
  rate: number;
  max_session_hours: number;
  waybar_poll_seconds: number;
  default_category: string | null;
  pomodoro_minutes: number;
  calendar_dir: string | null;
}

export interface DaySummary {
  date: string;
  category: string;
  total_minutes: number;
  notes: string[];
}

export interface CategorySummary {
  category: string;
  total_minutes: number;
}

export interface WaybarOutput {
  text: string;
  tooltip: string;
  class: 'active' | 'idle' | 'stale';
  percentage: number;
}

export type SessionState = 'active' | 'idle' | 'stale';

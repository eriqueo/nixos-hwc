import React, { useState, useEffect, useCallback } from 'react';
import { Box, Text, useInput } from 'ink';
import TextInput from 'ink-text-input';
import { getActiveSession, startSession, endSession, getSessionsByRange, getCategories } from '../db/queries.js';
import { elapsedMinutes, formatDuration, todayRange } from '../lib/time.js';
import { loadConfig } from '../config/index.js';
import type { Session, Category } from '../lib/types.js';

type Mode = 'normal' | 'clock-out-notes' | 'clock-out-category' | 'clock-in-category';

export function Dashboard(): React.ReactElement {
  const [active, setActive] = useState<Session | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [todaySessions, setTodaySessions] = useState<Session[]>([]);
  const [mode, setMode] = useState<Mode>('normal');
  const [inputValue, setInputValue] = useState('');
  const [pendingNotes, setPendingNotes] = useState('');
  const [categories, setCategories] = useState<Category[]>([]);
  const [catIdx, setCatIdx] = useState(0);
  const config = loadConfig();

  const refresh = useCallback(() => {
    const sess = getActiveSession();
    setActive(sess);
    if (sess) setElapsed(elapsedMinutes(sess.start_at));
    const range = todayRange();
    setTodaySessions(getSessionsByRange(range.from, range.to));
    setCategories(getCategories());
  }, []);

  // Poll every second
  useEffect(() => {
    refresh();
    const interval = setInterval(() => {
      const sess = getActiveSession();
      setActive(sess);
      if (sess) setElapsed(elapsedMinutes(sess.start_at));
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  // Refresh session list on mode changes (after clock in/out)
  useEffect(() => {
    if (mode === 'normal') refresh();
  }, [mode, refresh]);

  useInput((input, key) => {
    if (mode !== 'normal') return;

    if (input === 'i' && !active) {
      if (config.default_category) {
        startSession(config.default_category);
        refresh();
      } else {
        setCatIdx(0);
        setMode('clock-in-category');
      }
    }
    if (input === 'o' && active) {
      setInputValue('');
      setMode('clock-out-notes');
    }
  });

  const handleNotesSubmit = useCallback((value: string) => {
    setPendingNotes(value);
    setCatIdx(0);
    setMode('clock-out-category');
  }, []);

  const handleCategorySelect = useCallback((isClockIn: boolean) => {
    const cat = categories[catIdx]?.slug;
    if (isClockIn) {
      startSession(cat);
    } else {
      endSession(pendingNotes || null, cat);
    }
    setMode('normal');
    setInputValue('');
    setPendingNotes('');
  }, [catIdx, categories, pendingNotes]);

  // Category selector input
  useInput((input, key) => {
    if (mode !== 'clock-out-category' && mode !== 'clock-in-category') return;
    if (key.upArrow) setCatIdx((i) => Math.max(0, i - 1));
    if (key.downArrow) setCatIdx((i) => Math.min(categories.length - 1, i + 1));
    if (key.return) handleCategorySelect(mode === 'clock-in-category');
    if (key.escape) { setMode('normal'); setInputValue(''); }
  });

  const isStale = active && (elapsed / 60) >= config.max_session_hours;
  const todayTotal = todaySessions.reduce(
    (s, sess) => s + elapsedMinutes(sess.start_at, sess.end_at),
    0
  );

  return (
    <Box flexDirection="column">
      {/* Page heading */}
      <Box flexDirection="column" marginBottom={1}>
        <Text bold color="cyan">Dashboard</Text>
        <Text dimColor>Clock in/out · view today’s sessions</Text>
      </Box>

      {/* Timer */}
      <Box marginBottom={1}>
        {active ? (
          <Box>
            <Text color={isStale ? 'red' : 'green'} bold>
              ● {formatDuration(elapsed)}
            </Text>
            <Text color="gray"> {active.category ? `[${active.category}]` : ''}</Text>
            <Text color="gray"> since {new Date(active.start_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>
            {isStale && <Text color="red" bold> ⚠ STALE</Text>}
          </Box>
        ) : (
          <Text color="gray">○ Not clocked in</Text>
        )}
      </Box>

      {/* Prompts */}
      {mode === 'clock-out-notes' && (
        <Box marginBottom={1}>
          <Text color="yellow">Notes: </Text>
          <TextInput value={inputValue} onChange={setInputValue} onSubmit={handleNotesSubmit} placeholder="what did you work on? (enter to skip)" />
        </Box>
      )}

      {(mode === 'clock-out-category' || mode === 'clock-in-category') && (
        <Box flexDirection="column" marginBottom={1}>
          <Text color="yellow">Category (↑↓ enter):</Text>
          {categories.map((c, i) => (
            <Text key={c.slug} color={i === catIdx ? 'cyan' : 'gray'}>
              {i === catIdx ? '▸ ' : '  '}{c.label}
            </Text>
          ))}
        </Box>
      )}

      {/* Today's sessions */}
      <Box flexDirection="column" marginBottom={1}>
        <Text bold underline>Today — {formatDuration(todayTotal)}</Text>
        {todaySessions.filter(s => s.end_at).map((s) => {
          const dur = elapsedMinutes(s.start_at, s.end_at);
          const start = new Date(s.start_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
          const end = new Date(s.end_at!).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
          return (
            <Text key={s.id} color="gray">
              {start}-{end} {(s.category || 'other').padEnd(12)} {formatDuration(dur).padEnd(6)} {s.notes || ''}
            </Text>
          );
        })}
        {todaySessions.filter(s => s.end_at).length === 0 && <Text dimColor>No completed sessions today</Text>}
      </Box>

      {/* Hints */}
      {mode === 'normal' && (
        <Text dimColor>
          {active ? 'o:clock out' : 'i:clock in'} · 2:history · 3:export
        </Text>
      )}
      {mode === 'clock-out-notes' && (
        <Text dimColor>type notes then enter (leave blank to skip)</Text>
      )}
      {(mode === 'clock-in-category' || mode === 'clock-out-category') && (
        <Text dimColor>↑↓:select · enter:confirm · esc:cancel</Text>
      )}
    </Box>
  );
}

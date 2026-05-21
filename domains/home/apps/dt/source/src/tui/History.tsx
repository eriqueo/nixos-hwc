import React, { useState, useEffect, useCallback } from 'react';
import { Box, Text, useInput } from 'ink';
import TextInput from 'ink-text-input';
import { getSessionsByRange, updateSession, deleteSession, getCategories } from '../db/queries.js';
import { weekRange, elapsedMinutes, formatDuration } from '../lib/time.js';
import type { Session, Category } from '../lib/types.js';

type Mode = 'browse' | 'edit-notes' | 'edit-category' | 'confirm-delete';

export function History(): React.ReactElement {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [cursor, setCursor] = useState(0);
  const [weeksBack, setWeeksBack] = useState(0);
  const [mode, setMode] = useState<Mode>('browse');
  const [editValue, setEditValue] = useState('');
  const [categories, setCategories] = useState<Category[]>([]);
  const [catIdx, setCatIdx] = useState(0);

  const refresh = useCallback(() => {
    const range = weekRange(weeksBack);
    const sess = getSessionsByRange(range.from, range.to).filter(s => s.end_at);
    setSessions(sess.reverse()); // newest first
    setCategories(getCategories());
  }, [weeksBack]);

  useEffect(() => { refresh(); }, [refresh]);

  const selected = sessions[cursor];

  useInput((input, key) => {
    if (mode === 'browse') {
      if (key.upArrow) setCursor(i => Math.max(0, i - 1));
      if (key.downArrow) setCursor(i => Math.min(sessions.length - 1, i + 1));
      if (key.leftArrow) { setWeeksBack(w => w + 1); setCursor(0); }
      if (key.rightArrow && weeksBack > 0) { setWeeksBack(w => w - 1); setCursor(0); }
      if (input === 'n' && selected) {
        setEditValue(selected.notes || '');
        setMode('edit-notes');
      }
      if (input === 'c' && selected) {
        const idx = categories.findIndex(c => c.slug === selected.category);
        setCatIdx(Math.max(0, idx));
        setMode('edit-category');
      }
      if (input === 'd' && selected) {
        setMode('confirm-delete');
      }
    }

    if (mode === 'edit-category') {
      if (key.upArrow) setCatIdx(i => Math.max(0, i - 1));
      if (key.downArrow) setCatIdx(i => Math.min(categories.length - 1, i + 1));
      if (key.return) {
        updateSession(selected.id, { category: categories[catIdx].slug });
        setMode('browse');
        refresh();
      }
      if (key.escape) setMode('browse');
    }

    if (mode === 'confirm-delete') {
      if (input === 'y') {
        deleteSession(selected.id);
        setCursor(i => Math.max(0, i - 1));
        setMode('browse');
        refresh();
      }
      if (input === 'n' || key.escape) setMode('browse');
    }
  });

  const handleNotesSubmit = useCallback((value: string) => {
    if (selected) {
      updateSession(selected.id, { notes: value });
    }
    setMode('browse');
    refresh();
  }, [selected, refresh]);

  const weekLabel = weeksBack === 0 ? 'This Week' : `${weeksBack} Week${weeksBack > 1 ? 's' : ''} Ago`;
  const totalMins = sessions.reduce((s, sess) => s + elapsedMinutes(sess.start_at, sess.end_at), 0);

  return (
    <Box flexDirection="column">
      {/* Page heading */}
      <Box flexDirection="column" marginBottom={1}>
        <Text bold color="cyan">History</Text>
        <Text dimColor>Browse and edit completed sessions · navigate by week</Text>
      </Box>

      <Box marginBottom={1}>
        <Text bold underline>{weekLabel}</Text>
        <Text color="gray"> — {formatDuration(totalMins)} total</Text>
      </Box>

      {sessions.length === 0 && <Text dimColor>No sessions this week</Text>}

      {sessions.map((s, i) => {
        const dur = elapsedMinutes(s.start_at, s.end_at);
        const date = s.start_at.split('T')[0];
        const start = new Date(s.start_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const end = new Date(s.end_at!).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const isSel = i === cursor;
        return (
          <Text key={s.id} color={isSel ? 'cyan' : 'gray'} bold={isSel}>
            {isSel ? '▸ ' : '  '}{date} {start}-{end} {(s.category || 'other').padEnd(12)} {formatDuration(dur).padEnd(6)} {s.notes || ''}
          </Text>
        );
      })}

      {mode === 'edit-notes' && (
        <Box marginTop={1}>
          <Text color="yellow">Notes: </Text>
          <TextInput value={editValue} onChange={setEditValue} onSubmit={handleNotesSubmit} />
        </Box>
      )}

      {mode === 'edit-category' && (
        <Box flexDirection="column" marginTop={1}>
          <Text color="yellow">Category (↑↓ enter, esc cancel):</Text>
          {categories.map((c, i) => (
            <Text key={c.slug} color={i === catIdx ? 'cyan' : 'gray'}>
              {i === catIdx ? '▸ ' : '  '}{c.label}
            </Text>
          ))}
        </Box>
      )}

      {mode === 'confirm-delete' && (
        <Box marginTop={1}>
          <Text color="red">Delete session #{selected?.id}? (y/n)</Text>
        </Box>
      )}

      {mode === 'browse' && sessions.length > 0 && (
        <Box marginTop={1}>
          <Text dimColor>↑↓:select · ←→:week · n:edit notes · c:change category · d:delete</Text>
        </Box>
      )}
      {mode === 'browse' && sessions.length === 0 && (
        <Box marginTop={1}>
          <Text dimColor>←→:navigate weeks</Text>
        </Box>
      )}
      {mode === 'edit-notes' && (
        <Box marginTop={1}>
          <Text dimColor>enter:save · type to replace existing notes</Text>
        </Box>
      )}
      {mode === 'confirm-delete' && (
        <Box marginTop={1}>
          <Text dimColor>y:delete · n/esc:cancel</Text>
        </Box>
      )}
    </Box>
  );
}

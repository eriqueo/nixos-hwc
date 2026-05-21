import React, { useState, useCallback } from 'react';
import { Box, Text, useInput, useApp } from 'ink';
import { Dashboard } from './Dashboard.js';
import { History } from './History.js';
import { ExportView } from './Export.js';

const TABS = ['Dashboard', 'History', 'Export'] as const;
type Tab = typeof TABS[number];

export function App(): React.ReactElement {
  const [tab, setTab] = useState<Tab>('Dashboard');
  const [tabIdx, setTabIdx] = useState(0);
  const { exit } = useApp();

  const cycleTab = useCallback((dir: 1 | -1) => {
    setTabIdx((prev) => {
      const next = (prev + dir + TABS.length) % TABS.length;
      setTab(TABS[next]);
      return next;
    });
  }, []);

  useInput((input, key) => {
    if (input === 'q' && !key.ctrl) {
      exit();
      return;
    }
    if (key.tab) {
      cycleTab(key.shift ? -1 : 1);
    }
    // Number keys for direct tab access
    if (input === '1') { setTabIdx(0); setTab('Dashboard'); }
    if (input === '2') { setTabIdx(1); setTab('History'); }
    if (input === '3') { setTabIdx(2); setTab('Export'); }
  });

  return (
    <Box flexDirection="column" width="100%">
      {/* Title bar */}
      <Box paddingX={1}>
        <Text bold color="cyan">dt</Text>
        <Text color="gray"> — DataX Time Tracker</Text>
        <Box flexGrow={1} />
        <Text dimColor>q:quit · tab/⇧tab:cycle · 1-3:jump</Text>
      </Box>

      {/* Tab bar */}
      <Box borderStyle="single" borderBottom={false} paddingX={1}>
        {TABS.map((t, i) => (
          <Box key={t} marginRight={2}>
            <Text bold={i === tabIdx} color={i === tabIdx ? 'cyan' : 'gray'}>
              {i + 1}:{t}
            </Text>
          </Box>
        ))}
      </Box>

      {/* Content */}
      <Box borderStyle="single" borderTop={false} flexDirection="column" minHeight={20} paddingX={1}>
        {tab === 'Dashboard' && <Dashboard />}
        {tab === 'History' && <History />}
        {tab === 'Export' && <ExportView />}
      </Box>
    </Box>
  );
}

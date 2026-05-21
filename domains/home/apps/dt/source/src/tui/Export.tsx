import React, { useState, useCallback } from 'react';
import { Box, Text, useInput } from 'ink';
import TextInput from 'ink-text-input';
import { getDaySummaries, getCategorySummary } from '../db/queries.js';
import { dateRange, formatDuration, formatCurrency } from '../lib/time.js';
import { loadConfig } from '../config/index.js';
import { generateInvoiceAsync } from '../pdf/invoice.js';

type Step = 'from' | 'to' | 'confirm' | 'done';

export function ExportView(): React.ReactElement {
  const [step, setStep] = useState<Step>('from');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  const [fromInput, setFromInput] = useState('');
  const [toInput, setToInput] = useState('');
  const [result, setResult] = useState('');
  const [preview, setPreview] = useState<{ totalMins: number; days: number; amount: number } | null>(null);
  const config = loadConfig();

  const handleFromSubmit = useCallback((value: string) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      setResult('Invalid date format. Use YYYY-MM-DD.');
      return;
    }
    setFromDate(value);
    setStep('to');
  }, []);

  const handleToSubmit = useCallback((value: string) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      setResult('Invalid date format. Use YYYY-MM-DD.');
      return;
    }
    setToDate(value);

    // Preview
    const range = dateRange(fromDate, value);
    const cats = getCategorySummary(range.from, range.to);
    const totalMins = cats.reduce((s, c) => s + c.total_minutes, 0);
    const days = getDaySummaries(range.from, range.to);
    const uniqueDays = new Set(days.map(d => d.date)).size;

    setPreview({ totalMins, days: uniqueDays, amount: (totalMins / 60) * config.rate });
    setStep('confirm');
  }, [fromDate, config.rate]);

  useInput((input, key) => {
    if (step === 'confirm') {
      if (input === 'y') {
        const range = dateRange(fromDate, toDate);
        const days = getDaySummaries(range.from, range.to);
        const categories = getCategorySummary(range.from, range.to);
        const totalMinutes = categories.reduce((s, c) => s + c.total_minutes, 0);

        generateInvoiceAsync({ config, from: fromDate, to: toDate, days, categories, totalMinutes })
          .then((path) => {
            setResult(`✓ Saved: ${path}`);
            setStep('done');
          })
          .catch((err) => {
            setResult(`✗ Error: ${err.message}`);
            setStep('done');
          });
      }
      if (input === 'n' || key.escape) {
        setStep('from');
        setFromInput('');
        setToInput('');
        setPreview(null);
      }
    }
    if (step === 'done' && key.return) {
      setStep('from');
      setFromInput('');
      setToInput('');
      setResult('');
      setPreview(null);
    }
  });

  return (
    <Box flexDirection="column">
      {/* Page heading */}
      <Box flexDirection="column" marginBottom={1}>
        <Text bold color="cyan">Export</Text>
        <Text dimColor>Generate a PDF invoice for a date range → ~/Documents/datax-time/</Text>
      </Box>

      <Text bold underline>Invoice (PDF)</Text>
      <Box marginTop={1} />

      {step === 'from' && (
        <Box flexDirection="column">
          <Box>
            <Text color="yellow">From (YYYY-MM-DD): </Text>
            <TextInput value={fromInput} onChange={setFromInput} onSubmit={handleFromSubmit} placeholder="2026-05-01" />
          </Box>
          <Box marginTop={1}>
            <Text dimColor>Step 1 of 3 · type start date · enter:next</Text>
          </Box>
        </Box>
      )}

      {step === 'to' && (
        <Box flexDirection="column">
          <Text dimColor>From: {fromDate}</Text>
          <Box>
            <Text color="yellow">To (YYYY-MM-DD): </Text>
            <TextInput value={toInput} onChange={setToInput} onSubmit={handleToSubmit} placeholder="2026-05-31" />
          </Box>
          <Box marginTop={1}>
            <Text dimColor>Step 2 of 3 · type end date (inclusive) · enter:preview</Text>
          </Box>
        </Box>
      )}

      {step === 'confirm' && preview && (
        <Box flexDirection="column">
          <Text dimColor>Period: {fromDate} → {toDate}</Text>
          <Text>Days worked: {preview.days}</Text>
          <Text>Total hours: {formatDuration(preview.totalMins)}</Text>
          <Text>Rate: {formatCurrency(config.rate)}/hr</Text>
          <Text bold>Amount: {formatCurrency(preview.amount)}</Text>
          <Box marginTop={1}>
            <Text color="yellow">Generate invoice? (y/n)</Text>
          </Box>
          <Box marginTop={1}>
            <Text dimColor>Step 3 of 3 · y:write PDF · n/esc:start over</Text>
          </Box>
        </Box>
      )}

      {step === 'done' && (
        <Box flexDirection="column">
          <Text color={result.startsWith('✓') ? 'green' : 'red'}>{result}</Text>
          <Box marginTop={1}>
            <Text dimColor>enter:new invoice · q:close TUI · 1:back to dashboard</Text>
          </Box>
        </Box>
      )}

      {result && step !== 'done' && <Text color="red">{result}</Text>}
    </Box>
  );
}

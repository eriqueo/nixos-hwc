import { useState, useEffect, useCallback } from 'react';
import { C, mono } from '../styles/theme.js';
import { Box, Label, Divider } from './Section.jsx';
import { Toggle } from './Toggle.jsx';
import { Select } from './Select.jsx';

const API_BASE = import.meta.env.VITE_WEBHOOK_URL?.replace('/estimate-push', '')
  || localStorage.getItem('hwc-webhook-base')
  || '';
const API_KEY = import.meta.env.VITE_API_KEY || localStorage.getItem('hwc-api-key') || '';

// Responsive styles - these are baseline, components add mobile overrides
const inputStyle = {
  width: '100%',
  padding: '8px 12px',
  borderRadius: 4,
  border: `1px solid ${C.brd}`,
  backgroundColor: C.card2,
  color: C.txB,
  fontSize: 14,
  fontFamily: mono,
  outline: 'none',
  minHeight: 44,
};

const selectStyle = {
  ...inputStyle,
  cursor: 'pointer',
};

function FieldRow({ label, children }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0', gap: 12 }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono, minWidth: 90 }}>{label}</span>
      <div style={{ flex: 1 }}>{children}</div>
    </div>
  );
}

export function JobSelector({ s, set }) {
  const [customers, setCustomers] = useState([]);
  const [jobs, setJobs] = useState([]);
  const [loading, setLoading] = useState({ customers: false, jobs: false });
  const [error, setError] = useState(null);

  // Fetch customers on mount
  useEffect(() => {
    if (!API_BASE || !API_KEY) return;

    setLoading(l => ({ ...l, customers: true }));
    fetch(`${API_BASE}/jt-customers`, {
      headers: { 'x-api-key': API_KEY }
    })
      .then(r => r.json())
      .then(data => {
        setCustomers(data.customers || []);
        setLoading(l => ({ ...l, customers: false }));
      })
      .catch(err => {
        setError(`Failed to load customers: ${err.message}`);
        setLoading(l => ({ ...l, customers: false }));
      });
  }, []);

  // Fetch jobs when customer changes
  useEffect(() => {
    if (!API_BASE || !API_KEY || !s.customerId) {
      setJobs([]);
      return;
    }

    setLoading(l => ({ ...l, jobs: true }));
    fetch(`${API_BASE}/jt-jobs?customerId=${s.customerId}`, {
      headers: { 'x-api-key': API_KEY }
    })
      .then(r => r.json())
      .then(data => {
        setJobs(data.jobs || []);
        setLoading(l => ({ ...l, jobs: false }));
      })
      .catch(err => {
        setError(`Failed to load jobs: ${err.message}`);
        setLoading(l => ({ ...l, jobs: false }));
      });
  }, [s.customerId]);

  const handleCustomerChange = useCallback((customerId) => {
    const customer = customers.find(c => c.id === customerId);
    set('customerId', customerId);
    set('customerName', customer?.name || '');
    set('address', customer?.address || '');
    // Reset job selection when customer changes
    set('jobId', '');
    set('jobNumber', '');
    set('jobName', '');
  }, [customers, set]);

  const handleJobChange = useCallback((jobId) => {
    const job = jobs.find(j => j.id === jobId);
    set('jobId', jobId);
    set('jobNumber', job?.number || '');
    set('jobName', job?.name || '');
  }, [jobs, set]);

  const isNewJob = s.mode === 'new_job';

  // Show config warning if no API configured
  if (!API_BASE || !API_KEY) {
    return (
      <Box>
        <Label color={C.acc}>Job Selection</Label>
        <div style={{ padding: 10, backgroundColor: C.card2, borderRadius: 5, fontSize: 11, color: C.txD }}>
          <p style={{ margin: '0 0 8px' }}>Webhook not configured. Set environment variables:</p>
          <code style={{ display: 'block', fontSize: 10 }}>
            VITE_WEBHOOK_URL, VITE_API_KEY
          </code>
          <p style={{ margin: '8px 0 0', fontSize: 10 }}>
            Or set in console: <code>localStorage.setItem('hwc-webhook-base', 'https://...')</code>
          </p>
        </div>
      </Box>
    );
  }

  return (
    <Box>
      <Label color={C.acc}>Job Selection</Label>

      {error && (
        <div style={{ padding: 8, backgroundColor: 'rgba(238,107,110,0.1)', borderRadius: 4,
          marginBottom: 10, fontSize: 11, color: C.red }}>
          {error}
        </div>
      )}

      {/* Mode toggle */}
      <div style={{ display: 'flex', gap: 10, marginBottom: 12 }}>
        <button
          onClick={() => set('mode', 'existing')}
          style={{
            flex: 1, padding: '12px 12px', borderRadius: 6, cursor: 'pointer',
            border: `1px solid ${!isNewJob ? C.acc : C.brd}`,
            backgroundColor: !isNewJob ? 'rgba(201,149,107,0.15)' : 'transparent',
            color: !isNewJob ? C.acc : C.txD,
            fontSize: 12, fontWeight: 600, fontFamily: mono,
            minHeight: 48,
          }}
        >
          Existing Job
        </button>
        <button
          onClick={() => set('mode', 'new_job')}
          style={{
            flex: 1, padding: '12px 12px', borderRadius: 6, cursor: 'pointer',
            border: `1px solid ${isNewJob ? C.acc : C.brd}`,
            backgroundColor: isNewJob ? 'rgba(201,149,107,0.15)' : 'transparent',
            color: isNewJob ? C.acc : C.txD,
            fontSize: 12, fontWeight: 600, fontFamily: mono,
            minHeight: 48,
          }}
        >
          New Job
        </button>
      </div>

      {/* Customer dropdown */}
      <FieldRow label="Customer">
        <select
          value={s.customerId}
          onChange={e => handleCustomerChange(e.target.value)}
          disabled={loading.customers}
          style={selectStyle}
        >
          <option value="">{loading.customers ? 'Loading...' : '— Select Customer —'}</option>
          {customers.map(c => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>
      </FieldRow>

      {/* Existing job mode: job dropdown */}
      {!isNewJob && s.customerId && (
        <FieldRow label="Job">
          <select
            value={s.jobId}
            onChange={e => handleJobChange(e.target.value)}
            disabled={loading.jobs}
            style={selectStyle}
          >
            <option value="">{loading.jobs ? 'Loading...' : '— Select Job —'}</option>
            {jobs.map(j => (
              <option key={j.id} value={j.id}>{j.displayName}</option>
            ))}
          </select>
        </FieldRow>
      )}

      {/* New job mode: job name + address inputs */}
      {isNewJob && s.customerId && (
        <>
          <FieldRow label="Job Name">
            <input
              type="text"
              value={s.jobName}
              onChange={e => set('jobName', e.target.value)}
              placeholder="e.g. Master Bath Remodel"
              style={inputStyle}
            />
          </FieldRow>
          <FieldRow label="Address">
            <input
              type="text"
              value={s.address}
              onChange={e => set('address', e.target.value)}
              placeholder="e.g. 123 Main St, City, ST 12345"
              style={inputStyle}
            />
          </FieldRow>
        </>
      )}

      {/* Project type */}
      <Divider />
      <Select
        label="Project Type"
        value={s.projectType}
        onChange={v => set('projectType', v)}
        options={[
          { v: 'bathroom', l: 'Bathroom' },
          { v: 'kitchen',  l: 'Kitchen' },
          { v: 'deck',     l: 'Deck' },
          { v: 'general',  l: 'General' },
        ]}
      />

      {/* Selected job summary */}
      {s.jobId && !isNewJob && (
        <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5 }}>
          <div style={{ fontSize: 10, color: C.txD, marginBottom: 4 }}>Selected Job</div>
          <div style={{ fontSize: 12, color: C.acc, fontWeight: 600 }}>
            #{s.jobNumber} — {s.jobName}
          </div>
          <div style={{ fontSize: 11, color: C.tx }}>{s.customerName}</div>
        </div>
      )}
    </Box>
  );
}

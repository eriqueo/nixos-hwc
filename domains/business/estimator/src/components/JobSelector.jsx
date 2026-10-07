import { useState, useEffect, useCallback } from 'react';
import { C, mono } from '../styles/theme.js';
import { Box, Label, Divider } from './Section.jsx';
import { Toggle } from './Toggle.jsx';
import { Select } from './Select.jsx';
import { fetchCrmList, fetchCalculatorIntake } from '../api/crm.js';

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

export function JobSelector({ s, set, selectJob, prefill }) {
  const [customers, setCustomers] = useState([]);
  const [jobs, setJobs] = useState([]);
  const [loading, setLoading] = useState({ customers: false, jobs: false });
  const [error, setError] = useState(null);
  const [intakeStatus, setIntakeStatus] = useState('');
  const [intakeRetry, setIntakeRetry] = useState(0);

  useEffect(() => {
    if (s.mode !== 'existing' || !s.jobId || s.calculator_intake || s.calculator_input_status === 'manual') { setIntakeStatus(''); return; }
    const controller = new AbortController();
    setIntakeStatus('Loading customer inputs…');
    set('calculator_input_status','pending');
    fetchCalculatorIntake({ jobId: s.jobId, signal: controller.signal }).then(intake => {
      if (controller.signal.aborted) return;
      if (intake) prefill(intake);
      else set('calculator_input_status','none');
      setIntakeStatus(intake ? '' : 'No calculator inputs linked to this job.');
    }).catch(error => { if (!controller.signal.aborted) { setIntakeStatus(error.message); set('calculator_input_status','failed'); } });
    return () => controller.abort();
  }, [s.mode, s.jobId, s.calculator_intake, s.calculator_input_status === 'manual', prefill, set, intakeRetry]);

  // Fetch customers on mount
  useEffect(() => {
    if (!API_BASE || !API_KEY) return;

    setLoading(l => ({ ...l, customers: true }));
    const controller = new AbortController();
    setError(null);
    fetchCrmList({ base: API_BASE, key: API_KEY, resource: 'customers', signal: controller.signal })
      .then(rows => {
        if (controller.signal.aborted) return;
        setCustomers(rows);
        setLoading(l => ({ ...l, customers: false }));
      })
      .catch(err => {
        if (controller.signal.aborted) return;
        setError(`Failed to load customers: ${err.message}`);
        setLoading(l => ({ ...l, customers: false }));
      });
    return () => controller.abort();
  }, []);

  // Fetch jobs when customer changes
  useEffect(() => {
    if (!API_BASE || !API_KEY || !s.customerId) {
      setJobs([]);
      return;
    }

    setLoading(l => ({ ...l, jobs: true }));
    setJobs([]);
    const controller = new AbortController();
    setError(null);
    fetchCrmList({ base: API_BASE, key: API_KEY, resource: 'jobs', params: { customerId: s.customerId }, signal: controller.signal })
      .then(rows => {
        if (controller.signal.aborted) return;
        setJobs(rows);
        setLoading(l => ({ ...l, jobs: false }));
      })
      .catch(err => {
        if (controller.signal.aborted) return;
        setError(`Failed to load jobs: ${err.message}`);
        setLoading(l => ({ ...l, jobs: false }));
      });
    return () => controller.abort();
  }, [s.customerId]);

  const handleCustomerChange = useCallback((customerId) => {
    const customer = customers.find(c => c.id === customerId);
    selectJob({ mode: s.mode, customerId, customerName: customer?.name || '',
      ...(s.mode === 'existing' ? { address: customer?.address || '', jobNumber: '', jobName: '' } : {}),
      locationId: customer?.primaryLocationId || customer?.locations?.[0]?.id || '', jobId: '' });
  }, [customers, selectJob, s.mode]);

  const handleJobChange = useCallback((jobId) => {
    const job = jobs.find(j => j.id === jobId);
    selectJob({ mode: 'existing', customerId: s.customerId, customerName: s.customerName, locationId: s.locationId, address: s.address,
      jobId, jobNumber: job?.number || '', jobName: job?.name || '' });
  }, [jobs, selectJob, s.customerId, s.customerName, s.locationId, s.address]);

  const handleModeChange = useCallback((newMode) => {
    if (newMode === s.mode) return;
    selectJob({ mode: newMode, jobId: '', ...(newMode === 'existing' ? {jobNumber:'',jobName:''} : {}), customerId: newMode === 'new_customer' ? '' : s.customerId,
      customerName: newMode === 'new_customer' ? '' : s.customerName, locationId: newMode === 'new_customer' ? '' : s.locationId });
  }, [s.mode, s.customerId, s.customerName, s.locationId, selectJob]);

  const isNewCustomer = s.mode === 'new_customer';

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
        {[
          { id: 'existing', label: 'Existing Job' },
          { id: 'new_job', label: 'New Job' },
          { id: 'new_customer', label: 'New Customer' },
        ].map(m => {
          const active = s.mode === m.id;
          return (
            <button
              key={m.id}
              onClick={() => handleModeChange(m.id)}
              style={{
                flex: 1, padding: '12px 8px', borderRadius: 6, cursor: 'pointer',
                border: `1px solid ${active ? C.acc : C.brd}`,
                backgroundColor: active ? 'rgba(201,149,107,0.15)' : 'transparent',
                color: active ? C.acc : C.txD,
                fontSize: 11, fontWeight: 600, fontFamily: mono,
                minHeight: 48,
              }}
            >
              {m.label}
            </button>
          );
        })}
      </div>

      {/* Customer dropdown (existing + new_job modes) */}
      {!isNewCustomer && (
        <FieldRow label="Customer">
          <select
            aria-label="Customer"
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
      )}

      {/* Existing job mode: job dropdown */}
      {s.mode === 'existing' && s.customerId && (
        <FieldRow label="Job">
          <select
            aria-label="Job"
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
      {s.mode === 'new_job' && s.customerId && (
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

      {/* New customer mode: customer info + job name */}
      {isNewCustomer && (
        <>
          <FieldRow label="Name *">
            <input
              type="text"
              value={s.newCustomerName}
              onChange={e => set('newCustomerName', e.target.value)}
              placeholder="Customer name"
              style={inputStyle}
            />
          </FieldRow>
          <FieldRow label="Phone">
            <input
              type="tel"
              value={s.newCustomerPhone}
              onChange={e => set('newCustomerPhone', e.target.value)}
              placeholder="(406) 555-1234"
              style={inputStyle}
            />
          </FieldRow>
          <FieldRow label="Email">
            <input
              type="email"
              value={s.newCustomerEmail}
              onChange={e => set('newCustomerEmail', e.target.value)}
              placeholder="email@example.com"
              style={inputStyle}
            />
          </FieldRow>
          <FieldRow label="Street">
            <input
              type="text"
              value={s.newCustomerStreet}
              onChange={e => set('newCustomerStreet', e.target.value)}
              placeholder="123 Main St"
              style={inputStyle}
            />
          </FieldRow>
          <div style={{ display: 'flex', gap: 8, padding: '5px 0' }}>
            <div style={{ flex: 2 }}>
              <input
                type="text"
                value={s.newCustomerCity}
                onChange={e => set('newCustomerCity', e.target.value)}
                placeholder="City"
                style={inputStyle}
              />
            </div>
            <div style={{ flex: 0.7 }}>
              <input
                type="text"
                value={s.newCustomerState}
                onChange={e => set('newCustomerState', e.target.value)}
                placeholder="ST"
                maxLength={2}
                style={{ ...inputStyle, textAlign: 'center' }}
              />
            </div>
            <div style={{ flex: 1 }}>
              <input
                type="text"
                value={s.newCustomerZip}
                onChange={e => set('newCustomerZip', e.target.value)}
                placeholder="Zip"
                style={inputStyle}
              />
            </div>
          </div>
          <Divider />
          <FieldRow label="Job Name *">
            <input
              type="text"
              value={s.jobName}
              onChange={e => set('jobName', e.target.value)}
              placeholder="e.g. Master Bath Remodel"
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
      {s.mode === 'existing' && s.jobId && (
        <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5 }}>
          <div style={{ fontSize: 10, color: C.txD, marginBottom: 4 }}>Selected Job</div>
          <div style={{ fontSize: 12, color: C.acc, fontWeight: 600 }}>
            #{s.jobNumber} — {s.jobName}
          </div>
          <div style={{ fontSize: 11, color: C.tx }}>{s.customerName}</div>
        </div>
      )}

      {/* New customer summary */}
      {s.mode === 'existing' && s.jobId && intakeStatus && <div className="customer-inputs" role="status">
        <p>{intakeStatus}</p>
        {!intakeStatus.startsWith('Loading') && <button onClick={() => setIntakeRetry(v => v + 1)}>Reload customer inputs</button>}
        {!intakeStatus.startsWith('Loading') && <button onClick={() => set('calculator_input_status','manual')}>Use manual entry for this job</button>}
      </div>}
      {s.calculator_input_status === 'manual' && <div className="customer-inputs">
        <p>Manual entry selected. Replace preset values with measured scope before sending.</p>
        <button onClick={() => { set('calculator_input_status','pending'); setIntakeRetry(v => v + 1); }}>Reload customer inputs</button>
      </div>}
      {s.mode === 'existing' && s.calculator_intake && <div className="customer-inputs">
        <Label>Customer calculator inputs</Label>
        {s.calculator_intake.preliminary_budget && <p role="status">Preliminary budget: {s.calculator_intake.preliminary_budget.state}. Review assumptions and missing costs in JobTread before preparing a customer proposal.</p>}
        <p>Customer-reported measurements and preferences. Confirm scope, counts, measurements, and purchase costs on site.</p>
        {s.calculator_intake.rough_estimate && <p>Original rough range: ${s.calculator_intake.rough_estimate.low.toLocaleString()} – ${s.calculator_intake.rough_estimate.high.toLocaleString()}</p>}
        <dl>{Object.entries(s.calculator_intake.answers).filter(([key])=>key !== 'intake_version').map(([key,value]) => <div key={key}>
          <dt>{key.replaceAll('_',' ')}</dt><dd>{(Array.isArray(value) ? value.join(', ') : String(value ?? 'Not answered')).replaceAll('_',' ')}</dd>
        </div>)}</dl>
        <button aria-pressed={s.calculator_scope_checked === 'yes'} onClick={() => set('calculator_scope_checked', s.calculator_scope_checked === 'yes' ? 'no' : 'yes')}>
          {s.calculator_scope_checked === 'yes' ? 'Customer selections reviewed ✓' : 'Mark customer selections reviewed'}
        </button>
      </div>}

      {isNewCustomer && s.newCustomerName && (
        <div style={{ marginTop: 10, padding: 10, backgroundColor: C.card2, borderRadius: 5 }}>
          <div style={{ fontSize: 10, color: C.txD, marginBottom: 4 }}>New Customer</div>
          <div style={{ fontSize: 12, color: C.acc, fontWeight: 600 }}>
            {s.newCustomerName}
          </div>
          {s.jobName && <div style={{ fontSize: 11, color: C.tx }}>{s.jobName}</div>}
          {s.newCustomerPhone && <div style={{ fontSize: 10, color: C.txD }}>{s.newCustomerPhone}</div>}
        </div>
      )}
    </Box>
  );
}

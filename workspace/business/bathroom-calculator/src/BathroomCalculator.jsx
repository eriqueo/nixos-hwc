import React, { useState, useCallback } from 'react';

// Webhook endpoint
const WEBHOOK_URL = 'https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead';

// Pricing configuration
const PRICING = {
  project_type: {
    refresh: { base: 8000, multiplier: 1.0 },
    partial: { base: 15000, multiplier: 1.3 },
    full_gut: { base: 25000, multiplier: 1.6 },
  },
  bathroom_size: {
    small: { multiplier: 0.8 },      // <50 sqft
    medium: { multiplier: 1.0 },     // 50-80 sqft
    large: { multiplier: 1.3 },      // 80-120 sqft
    primary: { multiplier: 1.6 },    // >120 sqft
  },
  shower_tub: {
    tub_only: { add: 0 },
    shower_only: { add: 2000 },
    tub_shower: { add: 3500 },
    walk_in: { add: 6000 },
    freestanding: { add: 4500 },
  },
  tile_level: {
    budget: { multiplier: 0.85 },
    mid: { multiplier: 1.0 },
    premium: { multiplier: 1.25 },
    luxury: { multiplier: 1.5 },
  },
  fixtures: {
    basic: { add: 0 },
    upgraded: { add: 2500 },
    high_end: { add: 6000 },
  },
  features: {
    heated_floor: 1800,
    niches: 600,
    bench: 1200,
    rain_head: 800,
    body_jets: 2500,
    smart_toilet: 3500,
    custom_vanity: 4000,
    lighting_upgrade: 1500,
  },
};

// Step configuration
const STEPS = [
  {
    key: 'project_type',
    title: 'What type of remodel are you planning?',
    subtitle: 'This helps us understand the scope of work',
    type: 'single',
    options: [
      { value: 'refresh', label: 'Cosmetic Refresh', description: 'New paint, fixtures, vanity. Keep existing layout.' },
      { value: 'partial', label: 'Partial Remodel', description: 'Update some elements, minor layout changes.' },
      { value: 'full_gut', label: 'Full Gut Remodel', description: 'Complete tear-out to studs. New everything.' },
    ],
  },
  {
    key: 'bathroom_size',
    title: 'How large is your bathroom?',
    subtitle: 'Approximate square footage',
    type: 'single',
    options: [
      { value: 'small', label: 'Small', description: 'Under 50 sq ft (half bath or powder room)' },
      { value: 'medium', label: 'Medium', description: '50-80 sq ft (standard full bath)' },
      { value: 'large', label: 'Large', description: '80-120 sq ft (larger guest bath)' },
      { value: 'primary', label: 'Primary Suite', description: 'Over 120 sq ft (master bathroom)' },
    ],
  },
  {
    key: 'shower_tub',
    title: 'What shower or tub configuration?',
    subtitle: 'Select your preferred setup',
    type: 'single',
    options: [
      { value: 'tub_only', label: 'Tub Only', description: 'Standard bathtub, no shower' },
      { value: 'shower_only', label: 'Shower Only', description: 'Walk-in shower, no tub' },
      { value: 'tub_shower', label: 'Tub/Shower Combo', description: 'Tub with shower head' },
      { value: 'walk_in', label: 'Walk-In Shower', description: 'Large custom shower enclosure' },
      { value: 'freestanding', label: 'Freestanding Tub + Shower', description: 'Separate soaking tub and shower' },
    ],
  },
  {
    key: 'tile_level',
    title: 'What tile quality level?',
    subtitle: 'Affects materials cost significantly',
    type: 'single',
    options: [
      { value: 'budget', label: 'Budget Friendly', description: 'Basic ceramic, stock sizes' },
      { value: 'mid', label: 'Mid-Range', description: 'Quality porcelain, popular styles' },
      { value: 'premium', label: 'Premium', description: 'Large format, designer patterns' },
      { value: 'luxury', label: 'Luxury', description: 'Natural stone, custom mosaics' },
    ],
  },
  {
    key: 'fixtures',
    title: 'What fixture level?',
    subtitle: 'Faucets, showerheads, hardware',
    type: 'single',
    options: [
      { value: 'basic', label: 'Basic', description: 'Chrome, builder-grade brands' },
      { value: 'upgraded', label: 'Upgraded', description: 'Brushed nickel/black, quality brands' },
      { value: 'high_end', label: 'High-End', description: 'Designer brands, custom finishes' },
    ],
  },
  {
    key: 'features',
    title: 'Any special features?',
    subtitle: 'Select all that apply',
    type: 'multi',
    options: [
      { value: 'heated_floor', label: 'Heated Floor', description: 'Electric radiant floor heating' },
      { value: 'niches', label: 'Shower Niches', description: 'Built-in storage shelves' },
      { value: 'bench', label: 'Shower Bench', description: 'Built-in seating' },
      { value: 'rain_head', label: 'Rain Showerhead', description: 'Ceiling-mounted rain shower' },
      { value: 'body_jets', label: 'Body Jets', description: 'Multiple spray fixtures' },
      { value: 'smart_toilet', label: 'Smart Toilet', description: 'Bidet seat or smart toilet' },
      { value: 'custom_vanity', label: 'Custom Vanity', description: 'Built-to-order cabinetry' },
      { value: 'lighting_upgrade', label: 'Lighting Package', description: 'Recessed, sconces, dimming' },
    ],
  },
  {
    key: 'timeline',
    title: 'When do you want to start?',
    subtitle: 'Helps us plan capacity',
    type: 'single',
    options: [
      { value: 'asap', label: 'As Soon As Possible', description: 'Ready to get started' },
      { value: '1_3_months', label: '1-3 Months', description: 'Planning ahead' },
      { value: '3_6_months', label: '3-6 Months', description: 'Still researching' },
      { value: 'just_budgeting', label: 'Just Budgeting', description: 'Getting numbers for now' },
    ],
  },
];

// Calculate estimate
function calculateEstimate(projectState) {
  const { project_type, bathroom_size, shower_tub, tile_level, fixtures, features } = projectState;

  if (!project_type || !bathroom_size) return { low: 0, high: 0 };

  // Base from project type
  let base = PRICING.project_type[project_type]?.base || 15000;
  let multiplier = PRICING.project_type[project_type]?.multiplier || 1;

  // Size multiplier
  multiplier *= PRICING.bathroom_size[bathroom_size]?.multiplier || 1;

  // Tile level multiplier
  if (tile_level) {
    multiplier *= PRICING.tile_level[tile_level]?.multiplier || 1;
  }

  // Calculate subtotal
  let subtotal = base * multiplier;

  // Add shower/tub
  if (shower_tub) {
    subtotal += PRICING.shower_tub[shower_tub]?.add || 0;
  }

  // Add fixtures
  if (fixtures) {
    subtotal += PRICING.fixtures[fixtures]?.add || 0;
  }

  // Add features
  if (features && features.length > 0) {
    features.forEach(f => {
      subtotal += PRICING.features[f] || 0;
    });
  }

  // Range: -10% to +15%
  const low = Math.round(subtotal * 0.9 / 100) * 100;
  const high = Math.round(subtotal * 1.15 / 100) * 100;

  return { low, high };
}

// Option card component
function OptionCard({ option, selected, onClick, multi }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`
        w-full text-left p-4 rounded-xl border-2 transition-all duration-200
        ${selected
          ? 'border-brand-600 bg-brand-50 shadow-md'
          : 'border-gray-200 bg-white hover:border-brand-300 hover:shadow-sm'
        }
      `}
    >
      <div className="flex items-start gap-3">
        <div className={`
          mt-0.5 w-5 h-5 rounded-${multi ? 'md' : 'full'} border-2 flex-shrink-0
          flex items-center justify-center transition-colors
          ${selected
            ? 'border-brand-600 bg-brand-600'
            : 'border-gray-300'
          }
        `}>
          {selected && (
            <svg className="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          )}
        </div>
        <div>
          <div className="font-medium text-gray-900">{option.label}</div>
          <div className="text-sm text-gray-500 mt-0.5">{option.description}</div>
        </div>
      </div>
    </button>
  );
}

// Progress bar component
function ProgressBar({ current, total }) {
  const progress = ((current + 1) / total) * 100;
  return (
    <div className="mb-8">
      <div className="flex justify-between text-sm text-gray-500 mb-2">
        <span>Step {current + 1} of {total}</span>
        <span>{Math.round(progress)}% complete</span>
      </div>
      <div className="h-2 bg-gray-200 rounded-full overflow-hidden">
        <div
          className="h-full bg-brand-600 transition-all duration-300 ease-out"
          style={{ width: `${progress}%` }}
        />
      </div>
    </div>
  );
}

// Contact form component
function ContactForm({ contact, setContact, onSubmit, submitting, estimate }) {
  return (
    <div className="space-y-6">
      <div className="text-center mb-8">
        <h2 className="text-2xl font-bold text-gray-900 mb-2">Almost there!</h2>
        <p className="text-gray-600">Enter your info to see your personalized estimate</p>

        <div className="mt-6 p-4 bg-brand-50 rounded-xl border border-brand-200">
          <div className="text-sm text-brand-700 font-medium mb-1">Your estimate range</div>
          <div className="text-3xl font-bold text-brand-800">
            ${estimate.low.toLocaleString()} – ${estimate.high.toLocaleString()}
          </div>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Your Name <span className="text-red-500">*</span>
        </label>
        <input
          type="text"
          required
          value={contact.name}
          onChange={(e) => setContact({ ...contact, name: e.target.value })}
          className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder="John Smith"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Phone Number <span className="text-red-500">*</span>
        </label>
        <input
          type="tel"
          required
          value={contact.phone}
          onChange={(e) => setContact({ ...contact, phone: e.target.value })}
          className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder="(406) 555-1234"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Email Address
        </label>
        <input
          type="email"
          value={contact.email}
          onChange={(e) => setContact({ ...contact, email: e.target.value })}
          className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder="john@example.com"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Additional Notes
        </label>
        <textarea
          value={contact.notes}
          onChange={(e) => setContact({ ...contact, notes: e.target.value })}
          rows={3}
          className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder="Tell us about your project..."
        />
      </div>

      <button
        type="button"
        onClick={onSubmit}
        disabled={!contact.name || !contact.phone || submitting}
        className={`
          w-full py-4 px-6 rounded-xl font-semibold text-lg transition-all
          ${(!contact.name || !contact.phone || submitting)
            ? 'bg-gray-300 text-gray-500 cursor-not-allowed'
            : 'bg-brand-600 text-white hover:bg-brand-700 shadow-lg hover:shadow-xl'
          }
        `}
      >
        {submitting ? 'Submitting...' : 'Get My Estimate'}
      </button>

      <p className="text-xs text-gray-500 text-center">
        By submitting, you agree to receive a call or text from our team.
      </p>
    </div>
  );
}

// Thank you screen
function ThankYou({ contact, estimate }) {
  return (
    <div className="text-center py-12">
      <div className="w-20 h-20 mx-auto mb-6 bg-brand-100 rounded-full flex items-center justify-center">
        <svg className="w-10 h-10 text-brand-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
        </svg>
      </div>

      <h2 className="text-3xl font-bold text-gray-900 mb-2">
        Thanks, {contact.name.split(' ')[0]}!
      </h2>

      <p className="text-lg text-gray-600 mb-8">
        We'll reach out within 24 hours to discuss your project.
      </p>

      <div className="inline-block p-6 bg-brand-50 rounded-2xl border border-brand-200">
        <div className="text-sm text-brand-700 font-medium mb-2">Your estimate range</div>
        <div className="text-4xl font-bold text-brand-800 mb-1">
          ${estimate.low.toLocaleString()} – ${estimate.high.toLocaleString()}
        </div>
        <div className="text-sm text-gray-500">
          Final price depends on materials and specific requirements
        </div>
      </div>

      <div className="mt-10 space-y-3 text-left max-w-md mx-auto">
        <h3 className="font-semibold text-gray-900">What happens next?</h3>
        <div className="flex items-start gap-3">
          <div className="w-6 h-6 rounded-full bg-brand-600 text-white flex items-center justify-center text-sm font-medium flex-shrink-0">1</div>
          <p className="text-gray-600">We'll call to learn more about your vision</p>
        </div>
        <div className="flex items-start gap-3">
          <div className="w-6 h-6 rounded-full bg-brand-600 text-white flex items-center justify-center text-sm font-medium flex-shrink-0">2</div>
          <p className="text-gray-600">Schedule a free on-site consultation</p>
        </div>
        <div className="flex items-start gap-3">
          <div className="w-6 h-6 rounded-full bg-brand-600 text-white flex items-center justify-center text-sm font-medium flex-shrink-0">3</div>
          <p className="text-gray-600">Receive a detailed proposal within 48 hours</p>
        </div>
      </div>

      <div className="mt-10 pt-6 border-t border-gray-200">
        <p className="text-gray-500">
          Questions? Call us at <a href="tel:4065551234" className="text-brand-600 font-medium">(406) 555-1234</a>
        </p>
      </div>
    </div>
  );
}

// Main calculator component
export default function BathroomCalculator() {
  const [currentStep, setCurrentStep] = useState(0);
  const [projectState, setProjectState] = useState({
    project_type: null,
    bathroom_size: null,
    shower_tub: null,
    tile_level: null,
    fixtures: null,
    features: [],
    timeline: null,
  });
  const [contact, setContact] = useState({
    name: '',
    email: '',
    phone: '',
    notes: '',
  });
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const totalSteps = STEPS.length + 1; // +1 for contact form
  const isContactStep = currentStep === STEPS.length;
  const step = STEPS[currentStep];

  const estimate = calculateEstimate(projectState);

  const handleSelect = useCallback((key, value, isMulti) => {
    setProjectState(prev => {
      if (isMulti) {
        const current = prev[key] || [];
        const newValues = current.includes(value)
          ? current.filter(v => v !== value)
          : [...current, value];
        return { ...prev, [key]: newValues };
      }
      return { ...prev, [key]: value };
    });
  }, []);

  const canProceed = () => {
    if (isContactStep) return contact.name && contact.phone;
    const current = projectState[step.key];
    if (step.type === 'multi') return true; // Multi-select is optional
    return current !== null;
  };

  const handleNext = () => {
    if (currentStep < totalSteps - 1) {
      setCurrentStep(prev => prev + 1);
    }
  };

  const handleBack = () => {
    if (currentStep > 0) {
      setCurrentStep(prev => prev - 1);
    }
  };

  const handleSubmit = async () => {
    setSubmitting(true);
    setError(null);

    const payload = {
      contact,
      projectState,
      estimate,
      timestamp: new Date().toISOString(),
      source: 'website_calculator',
    };

    try {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error('Failed to submit');
      }

      setSubmitted(true);
    } catch (err) {
      console.error('Submit error:', err);
      setError('Something went wrong. Please try again or call us directly.');
    } finally {
      setSubmitting(false);
    }
  };

  if (submitted) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-gray-50 to-white py-12 px-4">
        <div className="max-w-lg mx-auto">
          <ThankYou contact={contact} estimate={estimate} />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-50 to-white py-8 px-4">
      <div className="max-w-lg mx-auto">
        {/* Header */}
        <div className="text-center mb-6">
          <h1 className="text-2xl font-bold text-gray-900">Bathroom Remodel Calculator</h1>
          <p className="text-gray-600">Get your estimate in 2 minutes</p>
        </div>

        {/* Progress */}
        <ProgressBar current={currentStep} total={totalSteps} />

        {/* Content */}
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-6">
          {isContactStep ? (
            <ContactForm
              contact={contact}
              setContact={setContact}
              onSubmit={handleSubmit}
              submitting={submitting}
              estimate={estimate}
            />
          ) : (
            <>
              <h2 className="text-xl font-bold text-gray-900 mb-1">{step.title}</h2>
              <p className="text-gray-500 mb-6">{step.subtitle}</p>

              <div className="space-y-3">
                {step.options.map(option => (
                  <OptionCard
                    key={option.value}
                    option={option}
                    multi={step.type === 'multi'}
                    selected={
                      step.type === 'multi'
                        ? (projectState[step.key] || []).includes(option.value)
                        : projectState[step.key] === option.value
                    }
                    onClick={() => handleSelect(step.key, option.value, step.type === 'multi')}
                  />
                ))}
              </div>
            </>
          )}

          {error && (
            <div className="mt-4 p-3 bg-red-50 text-red-700 rounded-lg text-sm">
              {error}
            </div>
          )}
        </div>

        {/* Navigation */}
        {!isContactStep && (
          <div className="flex gap-4">
            <button
              onClick={handleBack}
              disabled={currentStep === 0}
              className={`
                flex-1 py-3 px-6 rounded-xl font-medium transition-all
                ${currentStep === 0
                  ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
                  : 'bg-white border border-gray-300 text-gray-700 hover:bg-gray-50'
                }
              `}
            >
              Back
            </button>
            <button
              onClick={handleNext}
              disabled={!canProceed()}
              className={`
                flex-1 py-3 px-6 rounded-xl font-medium transition-all
                ${!canProceed()
                  ? 'bg-gray-300 text-gray-500 cursor-not-allowed'
                  : 'bg-brand-600 text-white hover:bg-brand-700'
                }
              `}
            >
              {currentStep === STEPS.length - 1 ? 'See My Estimate' : 'Next'}
            </button>
          </div>
        )}

        {/* Running estimate preview */}
        {!isContactStep && estimate.low > 0 && (
          <div className="mt-6 text-center text-sm text-gray-500">
            Current estimate: <span className="font-medium text-gray-900">${estimate.low.toLocaleString()} – ${estimate.high.toLocaleString()}</span>
          </div>
        )}
      </div>
    </div>
  );
}

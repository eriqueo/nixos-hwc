/**
 * Landing page / project creation
 */
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useStore } from '../lib/store';

export function Start() {
  const navigate = useNavigate();
  const { setProjectId, setFormConfig } = useStore();

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // Load form config on mount
    loadFormConfig();
  }, []);

  const loadFormConfig = async () => {
    try {
      const config = await api.getFormConfig();
      setFormConfig(config);
    } catch (error) {
      console.error('Failed to load form config:', error);
      alert('Failed to load the questionnaire. Please refresh the page.');
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!name || !email) {
      alert('Please provide your name and email');
      return;
    }

    setLoading(true);

    try {
      const { project_id, client_id } = await api.createProject({
        name,
        email,
        phone
      });

      setProjectId(project_id, client_id);
      navigate('/wizard');
    } catch (error) {
      console.error('Failed to create project:', error);
      alert('Failed to start project: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-brand-50 to-white flex items-center justify-center p-4">
      <div className="max-w-2xl w-full">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-5xl font-bold text-gray-900 mb-4">
            Plan Your Bathroom Remodel
          </h1>
          <p className="text-xl text-gray-600 mb-6">
            Get realistic cost estimates and expert guidance in just 5 minutes
          </p>

          {/* Features */}
          <div className="flex flex-wrap justify-center gap-4 text-sm text-gray-600">
            <div className="flex items-center gap-2">
              <span className="text-green-600">✓</span>
              <span>Instant cost estimates</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-green-600">✓</span>
              <span>Educational content</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-green-600">✓</span>
              <span>No obligations</span>
            </div>
          </div>
        </div>

        {/* Form */}
        <div className="card max-w-md mx-auto">
          <h2 className="text-2xl font-bold text-gray-900 mb-6">Let's Get Started</h2>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Your Name *</label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Jane Doe"
                className="input"
                required
              />
            </div>

            <div>
              <label className="label">Email Address *</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="jane@example.com"
                className="input"
                required
              />
            </div>

            <div>
              <label className="label">Phone Number (Optional)</label>
              <input
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="(406) 555-1234"
                className="input"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="btn btn-primary w-full mt-6"
            >
              {loading ? 'Starting...' : 'Start Planning →'}
            </button>
          </form>

          <p className="text-xs text-gray-500 text-center mt-4">
            We'll use your contact info only to send you your estimate and follow up if requested.
            No spam, ever.
          </p>
        </div>

        {/* Value props */}
        <div className="grid md:grid-cols-3 gap-6 mt-12">
          <div className="text-center">
            <div className="text-3xl mb-2">🎯</div>
            <h3 className="font-semibold text-gray-900 mb-1">Accurate Estimates</h3>
            <p className="text-sm text-gray-600">
              Based on real project data and local market rates
            </p>
          </div>
          <div className="text-center">
            <div className="text-3xl mb-2">📚</div>
            <h3 className="font-semibold text-gray-900 mb-1">Learn As You Go</h3>
            <p className="text-sm text-gray-600">
              Understand what goes into each decision
            </p>
          </div>
          <div className="text-center">
            <div className="text-3xl mb-2">💼</div>
            <h3 className="font-semibold text-gray-900 mb-1">No Pressure</h3>
            <p className="text-sm text-gray-600">
              Use the estimate however you want - we're here to help
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

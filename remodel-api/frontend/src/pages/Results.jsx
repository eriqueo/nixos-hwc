/**
 * Results page - shows cost estimate and project summary
 */
import React, { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../lib/api';

export function Results() {
  const { projectId } = useParams();
  const [estimate, setEstimate] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    loadEstimate();
  }, [projectId]);

  const loadEstimate = async () => {
    try {
      setLoading(true);
      // In a real flow, the estimate would be passed from wizard
      // For now, we'd need to recalculate or fetch from stored results
      // This is a simplified version
      const project = await api.getProject(projectId);

      if (project.estimated_total_min) {
        // Build estimate from project data
        const estimate = {
          project_id: projectId,
          summary: {
            scope_text: `Your ${project.bathroom_type || 'bathroom'} remodel`,
            complexity_band: project.complexity_band || 'medium',
            complexity_score: project.complexity_score || 0
          },
          cost: {
            total_min: project.estimated_total_min,
            total_max: project.estimated_total_max,
            labor_min: project.estimated_labor_min,
            labor_max: project.estimated_labor_max,
            materials_min: project.estimated_materials_min,
            materials_max: project.estimated_materials_max
          },
          modules: [], // Would need to fetch from project_cost_items
          education: {
            cost_drivers: [],
            questions_for_contractors: [
              "Are you licensed and insured?",
              "Can you provide references from similar projects?",
              "What's your estimated timeline?",
              "How do you handle change orders?",
              "What warranties do you offer?"
            ]
          }
        };
        setEstimate(estimate);
      } else {
        setError('Estimate not yet calculated for this project');
      }
    } catch (err) {
      console.error('Failed to load estimate:', err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDownloadPDF = async () => {
    try {
      const response = await api.generateReport(projectId);
      if (response.status === 'stub') {
        alert('PDF generation is not yet implemented. Coming soon!');
      }
    } catch (error) {
      alert('Failed to generate PDF: ' + error.message);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand-600 mx-auto mb-4"></div>
          <p className="text-gray-600">Loading your estimate...</p>
        </div>
      </div>
    );
  }

  if (error || !estimate) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="card max-w-md text-center">
          <div className="text-red-600 text-5xl mb-4">⚠️</div>
          <h2 className="text-xl font-bold text-gray-900 mb-2">Error Loading Estimate</h2>
          <p className="text-gray-600 mb-4">{error || 'Estimate not found'}</p>
          <button onClick={() => window.location.href = '/'} className="btn btn-primary">
            Start Over
          </button>
        </div>
      </div>
    );
  }

  const { summary, cost, education } = estimate;

  const formatCurrency = (amount) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      maximumFractionDigits: 0
    }).format(amount);
  };

  const complexityColor = {
    low: 'bg-green-100 text-green-800',
    medium: 'bg-yellow-100 text-yellow-800',
    high: 'bg-red-100 text-red-800'
  }[summary.complexity_band] || 'bg-gray-100 text-gray-800';

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-5xl mx-auto px-4">
        {/* Header */}
        <div className="text-center mb-12">
          <div className="inline-block px-4 py-2 bg-brand-100 text-brand-700 rounded-full text-sm font-medium mb-4">
            ✨ Your Bathroom Remodel Estimate
          </div>
          <h1 className="text-4xl font-bold text-gray-900 mb-4">
            Here's Your Plan
          </h1>
          <p className="text-lg text-gray-600 max-w-2xl mx-auto">
            {summary.scope_text}
          </p>
        </div>

        {/* Cost Summary - Big Numbers */}
        <div className="card mb-8 bg-gradient-to-br from-brand-600 to-brand-700 text-white">
          <div className="text-center mb-6">
            <h2 className="text-xl font-medium opacity-90 mb-4">Estimated Investment</h2>
            <div className="text-5xl font-bold mb-2">
              {formatCurrency(cost.total_min)} – {formatCurrency(cost.total_max)}
            </div>
            <div className="flex items-center justify-center gap-4 mt-4">
              <span className={`px-3 py-1 rounded-full text-sm font-medium ${complexityColor} bg-white`}>
                {summary.complexity_band} complexity
              </span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4 pt-6 border-t border-white/20">
            <div>
              <div className="text-sm opacity-75">Labor</div>
              <div className="text-xl font-semibold">
                {formatCurrency(cost.labor_min)} – {formatCurrency(cost.labor_max)}
              </div>
            </div>
            <div>
              <div className="text-sm opacity-75">Materials</div>
              <div className="text-xl font-semibold">
                {formatCurrency(cost.materials_min)} – {formatCurrency(cost.materials_max)}
              </div>
            </div>
          </div>
        </div>

        {/* Cost Breakdown */}
        {estimate.modules && estimate.modules.length > 0 && (
          <div className="card mb-8">
            <h3 className="text-xl font-bold text-gray-900 mb-4">Cost Breakdown</h3>
            <div className="space-y-3">
              {estimate.modules.map((module, idx) => (
                <div key={idx} className="flex items-center justify-between py-3 border-b border-gray-100 last:border-0">
                  <span className="font-medium text-gray-900">{module.label}</span>
                  <span className="text-gray-700">
                    {formatCurrency(module.total_min)} – {formatCurrency(module.total_max)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Educational Content */}
        {education.cost_drivers && education.cost_drivers.length > 0 && (
          <div className="card mb-8 bg-brand-50 border-brand-200">
            <h3 className="text-xl font-bold text-gray-900 mb-4">💡 What's Driving Your Cost</h3>
            <ul className="space-y-2">
              {education.cost_drivers.map((driver, idx) => (
                <li key={idx} className="flex items-start gap-3">
                  <span className="text-brand-600">•</span>
                  <span className="text-gray-700">{driver}</span>
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Questions for Contractors */}
        <div className="card mb-8">
          <h3 className="text-xl font-bold text-gray-900 mb-4">📋 Questions to Ask Contractors</h3>
          <ul className="space-y-2">
            {education.questions_for_contractors.map((question, idx) => (
              <li key={idx} className="flex items-start gap-3">
                <span className="text-gray-400">{idx + 1}.</span>
                <span className="text-gray-700">{question}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* CTAs */}
        <div className="grid md:grid-cols-2 gap-4">
          <button onClick={handleDownloadPDF} className="btn btn-outline w-full">
            📥 Download PDF Report
          </button>
          <a href="mailto:contact@heartwoodcraft.com?subject=Bathroom Remodel Inquiry" className="btn btn-primary w-full text-center">
            📞 Schedule a Call with Heartwood Craft
          </a>
        </div>

        {/* Footer note */}
        <div className="text-center mt-12 text-sm text-gray-500">
          <p>
            These are ballpark estimates based on typical projects. Your actual costs may vary based on
            site conditions, material availability, and specific design choices.
          </p>
          <p className="mt-2">
            Questions? Email us at{' '}
            <a href="mailto:contact@heartwoodcraft.com" className="text-brand-600 hover:underline">
              contact@heartwoodcraft.com
            </a>
          </p>
        </div>
      </div>
    </div>
  );
}

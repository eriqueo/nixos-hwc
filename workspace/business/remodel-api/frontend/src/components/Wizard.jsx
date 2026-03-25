/**
 * Main wizard component
 */
import React, { useEffect, useState } from 'react';
import { useStore } from '../lib/store';
import { api } from '../lib/api';
import { Question } from './Question';

export function Wizard() {
  const {
    currentStep,
    answers,
    projectId,
    formConfig,
    setAnswer,
    nextStep,
    prevStep,
    getCurrentStepConfig,
    isFirstStep,
    isLastStep,
    getProgress,
    setIsCalculating,
    setEstimate
  } = useStore();

  const [loading, setLoading] = useState(false);
  const stepConfig = getCurrentStepConfig();

  if (!stepConfig) {
    return (
      <div className="text-center py-12">
        <div className="text-gray-500">Loading wizard...</div>
      </div>
    );
  }

  const handleNext = async () => {
    if (!isLastStep()) {
      // Save progress to backend (incremental)
      if (projectId) {
        try {
          const currentAnswers = {};
          stepConfig.questions.forEach(q => {
            if (answers[q.key] !== undefined) {
              currentAnswers[q.key] = answers[q.key];
            }
          });

          await api.updateProjectAnswers(projectId, currentAnswers);
        } catch (error) {
          console.error('Failed to save answers:', error);
          // Continue anyway - answers are stored locally
        }
      }

      nextStep();
    } else {
      // Last step - calculate estimate
      await handleCalculateEstimate();
    }
  };

  const handleCalculateEstimate = async () => {
    if (!projectId) {
      alert('No project ID found. Please start over.');
      return;
    }

    setLoading(true);
    setIsCalculating(true);

    try {
      const estimate = await api.calculateEstimate(projectId, answers);
      setEstimate(estimate);

      // Navigate to results page (handled by parent router)
      window.location.href = `/results/${projectId}`;
    } catch (error) {
      console.error('Failed to calculate estimate:', error);
      alert('Failed to calculate estimate. Please try again.');
      setIsCalculating(false);
    } finally {
      setLoading(false);
    }
  };

  const canProceed = () => {
    // Check if all required questions have answers
    return stepConfig.questions.every(q => {
      if (!q.required) return true;
      const answer = answers[q.key];
      return answer !== undefined && answer !== null && answer !== '';
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-50 to-white">
      {/* Progress bar */}
      <div className="fixed top-0 left-0 right-0 z-50 bg-white shadow-sm">
        <div className="max-w-4xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-700">
              Step {currentStep + 1} of {formConfig.steps.length}
            </h3>
            <span className="text-sm text-gray-500">
              {Math.round(getProgress())}% Complete
            </span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div
              className="bg-brand-600 h-2 rounded-full transition-all duration-300"
              style={{ width: `${getProgress()}%` }}
            />
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="max-w-4xl mx-auto px-4 pt-32 pb-24">
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            {stepConfig.title}
          </h1>
          {stepConfig.subtitle && (
            <p className="text-lg text-gray-600">{stepConfig.subtitle}</p>
          )}
        </div>

        <div className="space-y-8">
          {stepConfig.questions.map((question) => (
            <Question
              key={question.key}
              question={question}
              value={answers[question.key]}
              onChange={(value) => setAnswer(question.key, value)}
            />
          ))}
        </div>

        {/* Navigation */}
        <div className="flex items-center justify-between mt-12 pt-8 border-t border-gray-200">
          <button
            onClick={prevStep}
            disabled={isFirstStep()}
            className={`btn btn-secondary ${isFirstStep() ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            ← Previous
          </button>

          <div className="text-sm text-gray-500">
            Step {currentStep + 1} of {formConfig.steps.length}
          </div>

          <button
            onClick={handleNext}
            disabled={!canProceed() || loading}
            className={`btn btn-primary ${!canProceed() || loading ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            {loading ? (
              'Calculating...'
            ) : isLastStep() ? (
              'Get My Estimate →'
            ) : (
              'Next →'
            )}
          </button>
        </div>

        {/* Help text */}
        {!canProceed() && (
          <div className="mt-4 text-center text-sm text-gray-500">
            Please answer all required questions to continue
          </div>
        )}
      </div>
    </div>
  );
}

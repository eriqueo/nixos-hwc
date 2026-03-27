/**
 * Reusable question components for the wizard
 */
import React from 'react';

/**
 * Single select (radio buttons)
 */
export function SingleSelect({ question, value, onChange }) {
  return (
    <div className="space-y-3">
      <label className="label">{question.label}</label>
      {question.description && (
        <p className="text-sm text-gray-600">{question.description}</p>
      )}

      <div className="space-y-2">
        {question.options.map((option) => (
          <label
            key={option.value}
            className={`
              card cursor-pointer transition-all duration-200
              ${value === option.value ? 'ring-2 ring-brand-500 bg-brand-50' : 'hover:border-brand-300'}
            `}
          >
            <div className="flex items-start gap-4">
              <input
                type="radio"
                name={question.key}
                value={option.value}
                checked={value === option.value}
                onChange={(e) => onChange(e.target.value)}
                className="mt-1 w-4 h-4 text-brand-600 focus:ring-brand-500"
              />
              <div className="flex-1">
                <div className="font-medium text-gray-900">{option.label}</div>
                {option.description && (
                  <div className="text-sm text-gray-600 mt-1">{option.description}</div>
                )}
                {option.education && (
                  <div className="text-sm text-brand-700 mt-2 bg-brand-50 p-3 rounded-lg">
                    💡 {option.education}
                  </div>
                )}
              </div>
            </div>
          </label>
        ))}
      </div>
    </div>
  );
}

/**
 * Multi select (checkboxes)
 */
export function MultiSelect({ question, value = [], onChange }) {
  const handleToggle = (optionValue) => {
    const newValue = value.includes(optionValue)
      ? value.filter(v => v !== optionValue)
      : [...value, optionValue];
    onChange(newValue);
  };

  return (
    <div className="space-y-3">
      <label className="label">{question.label}</label>
      {question.description && (
        <p className="text-sm text-gray-600">{question.description}</p>
      )}

      <div className="space-y-2">
        {question.options.map((option) => {
          const isSelected = value.includes(option.value);

          return (
            <label
              key={option.value}
              className={`
                card cursor-pointer transition-all duration-200
                ${isSelected ? 'ring-2 ring-brand-500 bg-brand-50' : 'hover:border-brand-300'}
              `}
            >
              <div className="flex items-start gap-4">
                <input
                  type="checkbox"
                  value={option.value}
                  checked={isSelected}
                  onChange={() => handleToggle(option.value)}
                  className="mt-1 w-4 h-4 text-brand-600 rounded focus:ring-brand-500"
                />
                <div className="flex-1">
                  <div className="font-medium text-gray-900">{option.label}</div>
                  {option.description && (
                    <div className="text-sm text-gray-600 mt-1">{option.description}</div>
                  )}
                  {option.education && (
                    <div className="text-sm text-brand-700 mt-2 bg-brand-50 p-3 rounded-lg">
                      💡 {option.education}
                    </div>
                  )}
                </div>
              </div>
            </label>
          );
        })}
      </div>
    </div>
  );
}

/**
 * Text area input
 */
export function TextArea({ question, value, onChange }) {
  return (
    <div className="space-y-3">
      <label className="label">{question.label}</label>
      {question.description && (
        <p className="text-sm text-gray-600 mb-2">{question.description}</p>
      )}

      <textarea
        value={value || ''}
        onChange={(e) => onChange(e.target.value)}
        placeholder={question.placeholder || ''}
        rows={6}
        className="input resize-none"
      />
    </div>
  );
}

/**
 * Render the appropriate question component based on type
 */
export function Question({ question, value, onChange }) {
  switch (question.type) {
    case 'single_select':
      return <SingleSelect question={question} value={value} onChange={onChange} />;

    case 'multi_select':
      return <MultiSelect question={question} value={value} onChange={onChange} />;

    case 'textarea':
      return <TextArea question={question} value={value} onChange={onChange} />;

    default:
      return (
        <div className="text-red-600">
          Unsupported question type: {question.type}
        </div>
      );
  }
}

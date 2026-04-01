import React from 'react';
import { createRoot } from 'react-dom/client';
import BathroomCalculator from './BathroomCalculator.jsx';

const container = document.getElementById('calculator-root');
if (container) {
  const root = createRoot(container);
  root.render(React.createElement(BathroomCalculator));
}

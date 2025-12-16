/**
 * Main App component with routing
 */
import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { Start } from './pages/Start';
import { Wizard } from './components/Wizard';
import { Results } from './pages/Results';

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<Start />} />
        <Route path="/wizard" element={<Wizard />} />
        <Route path="/results/:projectId" element={<Results />} />
      </Routes>
    </Router>
  );
}

export default App;

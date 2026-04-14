import React from 'react'
import ReactDOM from 'react-dom/client'
import BathroomCalculator from './BathroomCalculator'
import DeckCalculator from './DeckCalculator'

// Mount bathroom calculator if its root exists
const bathroomRoot = document.getElementById('calculator-root');
if (bathroomRoot) {
  ReactDOM.createRoot(bathroomRoot).render(
    <React.StrictMode>
      <BathroomCalculator />
    </React.StrictMode>,
  );
}

// Mount deck calculator if its root exists
const deckRoot = document.getElementById('deck-calculator-root');
if (deckRoot) {
  ReactDOM.createRoot(deckRoot).render(
    <React.StrictMode>
      <DeckCalculator />
    </React.StrictMode>,
  );
}

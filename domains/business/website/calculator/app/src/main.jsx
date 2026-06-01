import React from 'react'
import ReactDOM from 'react-dom/client'
import CalculatorRuntime from './CalculatorRuntime'
import EstimateSidebar from './EstimateSidebar'
import bathroomData from '../../../site_files/src/_data/calculator-bathroom.json'
import deckData from '../../../site_files/src/_data/calculator-deck.json'

// Mount-point → JSON config. Two known calculators today; a third is one
// JSON file + one entry here.
const MOUNTS = [
  { rootId: 'calculator-root',      data: bathroomData },
  { rootId: 'deck-calculator-root', data: deckData },
]

for (const { rootId, data } of MOUNTS) {
  const el = document.getElementById(rootId)
  if (!el) continue
  ReactDOM.createRoot(el).render(
    <React.StrictMode>
      <CalculatorRuntime data={data} sidebar={EstimateSidebar} />
    </React.StrictMode>,
  )
}

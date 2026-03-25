# Bathroom Remodel Planner - Frontend

React + Vite frontend for the bathroom remodel cost estimation tool.

## Features

- **Config-Driven Wizard**: Questions loaded from backend YAML config
- **Multi-Step Form**: Clean, user-friendly wizard interface
- **Real-Time Progress**: Visual progress bar and step indicators
- **Responsive Design**: Mobile-first with Tailwind CSS
- **State Management**: Zustand for lightweight global state
- **API Integration**: Clean API client with error handling

## Tech Stack

- **React 18** - UI framework
- **Vite** - Fast build tool
- **Tailwind CSS** - Utility-first styling
- **React Router** - Client-side routing
- **Zustand** - State management

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- Backend API running on `http://localhost:8000`

### Installation

```bash
cd frontend
npm install
```

### Development

```bash
npm run dev
```

The app will be available at `http://localhost:3000`.

API requests to `/api/*` are automatically proxied to `http://localhost:8000` (configured in `vite.config.js`).

### Build for Production

```bash
npm run build
```

Output will be in `dist/` directory. Serve with any static file server or Caddy.

## Project Structure

```
frontend/
├── src/
│   ├── components/
│   │   ├── Question.jsx      # Reusable question components
│   │   └── Wizard.jsx         # Main wizard orchestrator
│   ├── pages/
│   │   ├── Start.jsx          # Landing page / client info
│   │   └── Results.jsx        # Cost estimate results
│   ├── lib/
│   │   ├── api.js             # API client
│   │   └── store.js           # Zustand state management
│   ├── App.jsx                # Main app with routing
│   ├── main.jsx               # Entry point
│   └── index.css              # Tailwind + custom styles
├── index.html                 # HTML template
├── vite.config.js             # Vite configuration
├── tailwind.config.js         # Tailwind configuration
└── package.json
```

## Environment Variables

Create `.env.local` for custom API endpoint:

```
VITE_API_BASE=http://localhost:8000/api
```

## Customization

### Branding Colors

Edit `tailwind.config.js`:

```js
theme: {
  extend: {
    colors: {
      'brand': {
        50: '#f0f9ff',
        // ... your brand colors
      }
    }
  }
}
```

### Contact Email

Update in:
- `src/pages/Results.jsx` - CTA buttons
- `src/pages/Start.jsx` - Footer

### Logo

Replace placeholder in:
- `index.html` - Update favicon
- Add logo component to header

## Deployment

### With Caddy (Static Files)

```bash
# Build
npm run build

# Serve with Caddy
caddy file-server --root dist --listen :3000
```

### With Caddy Reverse Proxy (Production)

The NixOS module already configures Caddy to serve frontend static files:

```nix
services.caddy.virtualHosts."remodel.yourdomain.com" = {
  extraConfig = ''
    handle /api/* {
      reverse_proxy localhost:8001
    }
    handle /* {
      root * /var/www/remodel-planner
      file_server
      try_files {path} /index.html
    }
  '';
};
```

Copy `dist/` to `/var/www/remodel-planner` after building.

## API Integration

The frontend expects these endpoints:

- `GET /api/forms/bathroom` - Question tree config
- `POST /api/projects` - Create project
- `GET /api/projects/{id}` - Get project details
- `GET /api/projects/{id}/answers` - Get saved answers
- `PUT /api/projects/{id}/answers` - Update answers (incremental)
- `POST /api/projects/{id}/estimate` - Calculate estimate
- `POST /api/projects/{id}/report` - Generate PDF

See `src/lib/api.js` for implementation.

## State Management

Using Zustand for lightweight state:

- `projectId` - Current project ID
- `currentStep` - Wizard step index
- `answers` - User's answers (key-value)
- `formConfig` - Question tree config from API
- `estimate` - Calculated cost estimate

See `src/lib/store.js` for full state structure.

## Troubleshooting

### API Connection Issues

Check that:
1. Backend is running on `http://localhost:8000`
2. CORS is enabled in backend (should be by default)
3. Vite proxy is configured in `vite.config.js`

### Build Errors

Clear cache and rebuild:
```bash
rm -rf node_modules dist
npm install
npm run build
```

### Styling Issues

Tailwind not applying? Check:
1. `tailwind.config.js` content paths
2. `@tailwind` directives in `index.css`
3. PostCSS is configured

## Contributing

This frontend is designed to be modular:
- Add new question types in `components/Question.jsx`
- Add new pages in `pages/`
- Extend state in `lib/store.js`
- Add API methods in `lib/api.js`

## License

(Same as parent project)

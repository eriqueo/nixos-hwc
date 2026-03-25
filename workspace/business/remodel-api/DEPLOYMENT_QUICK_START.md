# Quick Deployment Outline

**Fast-track guide to deploy the Bathroom Remodel Planner on your NixOS server.**

For complete details, see [DEPLOYMENT.md](./DEPLOYMENT.md)

---

## Overview

You'll deploy:
1. **Backend API** - FastAPI in Podman container
2. **Frontend** - React SPA served by Caddy
3. **Database** - PostgreSQL
4. **PDFs** - Persistent storage at `/var/lib/remodel-api/pdfs`

---

## Pre-Deployment (On Your Local Machine)

### 1. Customize Branding & Pricing

**Critical files to edit:**

```bash
# 1. Update company branding
vim app/templates/bathroom_report.html
# Search for "Heartwood Craft" and replace with your company name
# Update email, phone, website

# 2. Update pricing for your market (CRITICAL!)
vim config/cost_rules_seed.sql
# Adjust base_cost_min/max values to match your area

# 3. Update frontend branding
vim frontend/src/pages/Start.jsx
vim frontend/src/pages/Results.jsx
# Update contact info

# 4. Customize colors (optional)
vim frontend/tailwind.config.js
```

### 2. Test Locally

```bash
# Backend
pip install -r requirements.txt
createdb remodel_test
psql -d remodel_test -f migrations/001_initial_schema.sql
psql -d remodel_test -f config/cost_rules_seed.sql
uvicorn app.main:app --reload

# Frontend (in new terminal)
cd frontend
npm install
npm run dev

# Test at http://localhost:3000
# Complete a full wizard → estimate → PDF download
```

### 3. Build for Production

```bash
# Build frontend
cd frontend
npm run build

# Build backend container
cd ..
docker build -t remodel-api:latest .

# Export for server
docker save remodel-api:latest | gzip > remodel-api-latest.tar.gz
```

---

## Server Deployment (On Your NixOS Server)

### Step 1: Copy Files

```bash
# On local machine:
# 1. Copy container image
scp remodel-api-latest.tar.gz your-server:/tmp/

# 2. Copy frontend
rsync -avz frontend/dist/ your-server:/tmp/remodel-frontend/

# 3. Copy migrations & config
scp migrations/001_initial_schema.sql your-server:/tmp/
scp config/cost_rules_seed.sql your-server:/tmp/
```

### Step 2: Server Setup

```bash
# SSH to server
ssh your-server

# Load container
sudo podman load < /tmp/remodel-api-latest.tar.gz

# Create directories
sudo mkdir -p /var/www/remodel-planner
sudo mkdir -p /var/lib/remodel-api/pdfs

# Copy frontend files
sudo cp -r /tmp/remodel-frontend/* /var/www/remodel-planner/
sudo chown -R caddy:caddy /var/www/remodel-planner

# Set up database
sudo -u postgres createdb remodel
sudo -u postgres psql -d remodel -f /tmp/001_initial_schema.sql
sudo -u postgres psql -d remodel -f /tmp/cost_rules_seed.sql

# Create database user & set password
sudo -u postgres psql <<EOF
CREATE USER remodel WITH ENCRYPTED PASSWORD 'CHANGE-THIS-PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE remodel TO remodel;
\c remodel
GRANT ALL ON SCHEMA public TO remodel;
EOF
```

### Step 3: NixOS Configuration

Add to `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  # PostgreSQL
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
  };

  # Podman container for API
  virtualisation.oci-containers = {
    backend = "podman";
    containers.remodel-api = {
      image = "remodel-api:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8001:8000" ];

      environment = {
        DATABASE_URL = "postgresql://remodel:CHANGE-THIS-PASSWORD@host.containers.internal:5432/remodel";
      };

      extraOptions = [
        "--network=slirp4netns:allow_host_loopback=true"
      ];

      volumes = [
        "/var/lib/remodel-api/pdfs:/app/pdfs"
      ];
    };
  };

  # Caddy reverse proxy
  services.caddy = {
    enable = true;
    virtualHosts."remodel.yourdomain.com" = {
      extraConfig = ''
        # API endpoints
        handle /api/* {
          reverse_proxy localhost:8001
        }

        # PDF downloads
        handle /pdfs/* {
          reverse_proxy localhost:8001
        }

        # Frontend
        handle /* {
          root * /var/www/remodel-planner
          try_files {path} /index.html
          file_server
        }
      '';
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

### Step 4: Deploy

```bash
# Rebuild NixOS
sudo nixos-rebuild switch

# Check services
systemctl status podman-remodel-api.service
systemctl status caddy.service
systemctl status postgresql.service

# Test API
curl http://localhost:8001/health

# Test frontend
curl http://localhost/

# Check logs
journalctl -u podman-remodel-api -n 50
```

### Step 5: DNS & SSL

1. Point your domain to your server's IP
2. Wait for DNS to propagate
3. Caddy will automatically get SSL certificate from Let's Encrypt
4. Test: `https://remodel.yourdomain.com`

---

## Verification Checklist

Test these after deployment:

- [ ] Can access homepage: `https://remodel.yourdomain.com`
- [ ] Can enter client info and start wizard
- [ ] All wizard steps load correctly
- [ ] Can submit wizard and get estimate
- [ ] Cost ranges look reasonable
- [ ] Can download PDF report
- [ ] PDF opens and looks professional
- [ ] Mobile responsive (test on phone)
- [ ] SSL certificate is valid

---

## Common Issues

### API Won't Start

```bash
# Check logs
podman logs remodel-api

# Common fix: Database connection
# Edit the DATABASE_URL in your NixOS config
# Make sure password matches what you set
```

### Frontend Shows 404

```bash
# Check files copied
ls /var/www/remodel-planner/

# Should see: index.html, assets/, etc.

# Check Caddy config
systemctl status caddy
journalctl -u caddy -n 50
```

### PDF Download Fails

```bash
# Check PDF directory exists
ls -la /var/lib/remodel-api/pdfs

# Check permissions
sudo chown -R root:root /var/lib/remodel-api
sudo chmod -R 755 /var/lib/remodel-api

# Check WeasyPrint in container
podman exec remodel-api python -c "import weasyprint; print('OK')"
```

### Pricing Seems Off

```bash
# Re-check cost rules in database
psql -U remodel -d remodel -c "SELECT * FROM cost_rules WHERE active = true LIMIT 5;"

# Re-seed if needed
psql -U remodel -d remodel -f /tmp/cost_rules_seed.sql
```

---

## Quick Commands Reference

```bash
# Restart API
systemctl restart podman-remodel-api

# Restart Caddy
systemctl restart caddy

# View logs
journalctl -u podman-remodel-api -f

# Access database
psql -U remodel -d remodel

# Update frontend (after changes)
rsync -avz frontend/dist/ server:/var/www/remodel-planner/
```

---

## Next Steps After Deployment

1. **Test thoroughly** - Run through the wizard 5+ times
2. **Calibrate pricing** - Compare estimates to your real projects
3. **Refine content** - Update educational text based on client feedback
4. **Set up monitoring** - Watch logs for errors
5. **Backup database** - Set up automated backups
6. **Share with beta testers** - Get feedback before full launch

---

## Need Help?

1. Check [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed troubleshooting
2. Review logs: `journalctl -u podman-remodel-api -n 100`
3. Test each component independently (DB, API, frontend)
4. Check the main [README.md](./README.md) for architecture details

---

**Estimated deployment time:** 1-2 hours (first time)

**Key to success:** Test locally first, customize pricing before deploying!

Good luck! 🚀

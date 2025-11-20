# Bathroom Remodel Planner - Deployment Guide

Complete guide to deploying the full-stack bathroom remodel planner on your NixOS server.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Testing](#local-testing)
3. [Building for Production](#building-for-production)
4. [NixOS Server Deployment](#nixos-server-deployment)
5. [Database Setup](#database-setup)
6. [Customization Checklist](#customization-checklist)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### On Your Local Machine
- Git
- Docker (for building container images)
- Node.js 18+ and npm (for frontend)
- PostgreSQL client tools (for database setup)

### On Your NixOS Server
- NixOS 23.05 or later
- PostgreSQL enabled
- Caddy web server
- Podman container runtime
- Agenix (for secrets management)

---

## Local Testing

Before deploying to production, test everything locally:

### 1. Backend Testing

```bash
cd remodel-api

# Create virtual environment
python -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install dependencies
pip install -r requirements.txt

# Set up database
createdb remodel_test
psql -d remodel_test -f migrations/001_initial_schema.sql
psql -d remodel_test -f config/cost_rules_seed.sql

# Run API
export DATABASE_URL="postgresql://localhost/remodel_test"
uvicorn app.main:app --reload
```

Test at `http://localhost:8000/docs`

### 2. Frontend Testing

```bash
cd frontend

# Install dependencies
npm install

# Run dev server (auto-proxies to backend on :8000)
npm run dev
```

Test at `http://localhost:3000`

### 3. End-to-End Test

1. Fill out the wizard
2. Submit and get estimate
3. Click "Download PDF"
4. Check that PDF generates correctly

**Fix any issues before deploying!**

---

## Building for Production

### 1. Build Frontend

```bash
cd frontend

# Install dependencies
npm install

# Build for production
npm run build

# Output will be in dist/
ls dist/
```

### 2. Build Backend Container

```bash
cd ..  # Back to remodel-api/

# Build Docker image
docker build -t remodel-api:latest .

# Test the container locally
docker run -d \
  --name remodel-api-test \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql://user:pass@host.docker.internal/remodel" \
  -v $(pwd)/pdfs:/app/pdfs \
  remodel-api:latest

# Check logs
docker logs remodel-api-test

# Stop and remove
docker stop remodel-api-test
docker rm remodel-api-test
```

### 3. Export Container Image

For NixOS Podman, export the image:

```bash
# Save image to tarball
docker save remodel-api:latest | gzip > remodel-api-latest.tar.gz

# Copy to your server
scp remodel-api-latest.tar.gz your-server:/tmp/

# On the server, load into Podman
ssh your-server
podman load < /tmp/remodel-api-latest.tar.gz
```

---

## NixOS Server Deployment

### Step 1: Prepare Directory Structure

On your NixOS server:

```bash
# Create directories
sudo mkdir -p /var/www/remodel-planner
sudo mkdir -p /var/lib/remodel-api/pdfs

# Set permissions
sudo chown -R caddy:caddy /var/www/remodel-planner
sudo chown -R root:root /var/lib/remodel-api
```

### Step 2: Copy Frontend Files

From your local machine:

```bash
# Copy built frontend to server
cd frontend
rsync -avz dist/ your-server:/var/www/remodel-planner/

# Or use scp
scp -r dist/* your-server:/var/www/remodel-planner/
```

### Step 3: Set Up Database

On your NixOS server:

```bash
# Create database and user
sudo -u postgres psql <<EOF
CREATE DATABASE remodel;
CREATE USER remodel WITH ENCRYPTED PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE remodel TO remodel;
\c remodel
GRANT ALL ON SCHEMA public TO remodel;
EOF

# Run migrations
sudo -u postgres psql -d remodel -f /path/to/migrations/001_initial_schema.sql

# Seed cost rules (AFTER customizing prices!)
sudo -u postgres psql -d remodel -f /path/to/config/cost_rules_seed.sql
```

### Step 4: Configure Secrets with Agenix

Create a secret for the database password:

```nix
# In your secrets.nix
{
  "remodel-db-password.age".publicKeys = [ /* your keys */ ];
}
```

Encrypt the secret:

```bash
agenix -e remodel-db-password.age
# Enter your database password
```

### Step 5: Add NixOS Configuration

Add to your NixOS configuration:

```nix
# /etc/nixos/configuration.nix or your modular config

{ config, pkgs, ... }:

{
  # Import the remodel API module
  imports = [
    /path/to/remodel-api/nix/container.nix
  ];

  # Enable PostgreSQL
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
  };

  # Configure remodel API
  services.remodel-api = {
    enable = true;
    domain = "remodel.yourdomain.com";  # Change this!
    port = 8001;

    # Use agenix secret (recommended)
    # databasePasswordFile = config.age.secrets.remodel-db-password.path;

    # Or hardcode for testing (NOT recommended for production)
    databasePassword = "your-secure-password";
  };

  # Ensure Caddy is enabled
  services.caddy.enable = true;

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

### Step 6: Rebuild NixOS

```bash
# Rebuild and switch
sudo nixos-rebuild switch

# Check services
systemctl status podman-remodel-api.service
systemctl status caddy.service
systemctl status postgresql.service
```

### Step 7: Verify Deployment

```bash
# Check API is running
curl http://localhost:8001/health

# Check frontend is served
curl http://localhost/

# Check PDF directory exists
ls -la /var/lib/remodel-api/pdfs

# Check Caddy logs
journalctl -u caddy -n 50
```

---

## Database Setup

### Production Database Configuration

```sql
-- Create database with proper ownership
CREATE DATABASE remodel
  WITH OWNER = remodel
  ENCODING = 'UTF8'
  LC_COLLATE = 'en_US.UTF-8'
  LC_CTYPE = 'en_US.UTF-8'
  TEMPLATE = template0;

-- Connect to database
\c remodel

-- Run schema migration
\i /path/to/migrations/001_initial_schema.sql

-- Seed cost rules (CUSTOMIZE FIRST!)
\i /path/to/config/cost_rules_seed.sql

-- Verify tables
\dt

-- Check cost rules
SELECT engine, module_key, COUNT(*) as rules
FROM cost_rules
WHERE active = true
GROUP BY engine, module_key;
```

### Backup Strategy

Set up automated backups:

```nix
# In your NixOS config
services.postgresqlBackup = {
  enable = true;
  databases = [ "remodel" ];
  startAt = "daily";
  location = "/var/backup/postgresql";
};
```

Or manual backup:

```bash
# Backup
pg_dump -U remodel remodel > remodel_backup_$(date +%Y%m%d).sql

# Restore
psql -U remodel remodel < remodel_backup_20250120.sql
```

---

## Customization Checklist

Before going live, customize these:

### 1. Branding & Contact Info

**Backend Template** (`app/templates/bathroom_report.html`):
- [ ] Company name (search for "Heartwood Craft")
- [ ] Email address
- [ ] Phone number
- [ ] Website URL
- [ ] Logo (optional: add image)

**Frontend** (`frontend/src/`):
- [ ] `pages/Start.jsx` - Contact info in footer
- [ ] `pages/Results.jsx` - Email/call CTAs
- [ ] `tailwind.config.js` - Brand colors

### 2. Pricing (CRITICAL!)

Edit `config/cost_rules_seed.sql`:

```sql
-- Example: Update tub-to-shower pricing for your market
UPDATE cost_rules
SET base_cost_min = 3000, base_cost_max = 5000
WHERE module_key = 'tub_to_shower' AND rule_key = 'tiled_shower_pan';
```

**Test with 3-5 past projects to calibrate!**

### 3. Educational Content

Edit `config/bathroom_questions.yaml`:
- [ ] Update descriptions with your expertise
- [ ] Add market-specific advice
- [ ] Update common pitfalls section

### 4. Domain & SSL

```nix
services.remodel-api.domain = "remodel.yourdomain.com";
```

Make sure DNS points to your server!

Caddy handles SSL automatically via Let's Encrypt.

---

## Monitoring & Maintenance

### Logs

```bash
# API container logs
podman logs remodel-api

# Caddy logs
journalctl -u caddy -f

# PostgreSQL logs
journalctl -u postgresql -f

# All together
journalctl -u podman-remodel-api -u caddy -u postgresql -f
```

### Metrics to Watch

- **Disk space**: PDFs will accumulate in `/var/lib/remodel-api/pdfs`
- **Database size**: `SELECT pg_size_pretty(pg_database_size('remodel'));`
- **Error rate**: Check logs for 500 errors
- **Lead volume**: `SELECT COUNT(*) FROM projects WHERE created_at > NOW() - INTERVAL '7 days';`

### Updating the Application

When you make changes:

```bash
# 1. Update code locally
# 2. Rebuild containers
docker build -t remodel-api:latest .
docker save remodel-api:latest | gzip > remodel-api-latest.tar.gz

# 3. Copy to server
scp remodel-api-latest.tar.gz your-server:/tmp/

# 4. On server
podman load < /tmp/remodel-api-latest.tar.gz
systemctl restart podman-remodel-api

# 5. For frontend updates
cd frontend && npm run build
rsync -avz dist/ your-server:/var/www/remodel-planner/
```

### Database Migrations

For schema changes:

```bash
# Create new migration file
# migrations/002_add_feature.sql

# Apply on server
psql -U remodel -d remodel -f migrations/002_add_feature.sql
```

---

## Troubleshooting

### API Not Starting

```bash
# Check container status
podman ps -a | grep remodel-api

# Check logs
podman logs remodel-api

# Common issues:
# - Database connection: Check DATABASE_URL
# - Port conflict: Check port 8001 is free
# - Permissions: Check /var/lib/remodel-api ownership
```

### PDF Generation Fails

```bash
# Check PDF directory
ls -la /var/lib/remodel-api/pdfs

# Check permissions
sudo chown -R root:root /var/lib/remodel-api
sudo chmod -R 755 /var/lib/remodel-api

# Check WeasyPrint dependencies (in container)
podman exec remodel-api python -c "import weasyprint; print('OK')"
```

### Frontend Not Loading

```bash
# Check Caddy config
caddy validate --config /etc/caddy/Caddyfile

# Check files exist
ls /var/www/remodel-planner/

# Check Caddy logs
journalctl -u caddy -n 100

# Test direct file access
curl http://localhost/index.html
```

### Database Connection Issues

```bash
# Test connection from API container
podman exec remodel-api python -c "
import asyncpg
import asyncio
async def test():
    conn = await asyncpg.connect('postgresql://remodel:pass@host.containers.internal/remodel')
    print(await conn.fetchval('SELECT 1'))
asyncio.run(test())
"

# Check PostgreSQL is listening
sudo netstat -tlnp | grep 5432

# Check pg_hba.conf allows connections
sudo cat /var/lib/postgresql/data/pg_hba.conf
```

### Cost Estimates Seem Wrong

```bash
# Check loaded rules
psql -U remodel -d remodel -c "
SELECT module_key, COUNT(*) as rule_count, MIN(base_cost_min) as min_cost, MAX(base_cost_max) as max_cost
FROM cost_rules
WHERE active = true
GROUP BY module_key;
"

# Re-seed with updated prices
psql -U remodel -d remodel -f config/cost_rules_seed.sql
```

---

## Performance Optimization

### For High Traffic

```nix
# Increase container resources
virtualisation.oci-containers.containers.remodel-api = {
  extraOptions = [
    "--memory=2g"
    "--cpus=2"
  ];
};
```

### Database Indexing

Already included in schema, but verify:

```sql
-- Check indexes exist
\di

-- Analyze query performance
EXPLAIN ANALYZE SELECT * FROM projects WHERE created_at > NOW() - INTERVAL '30 days';
```

### CDN for PDFs (Optional)

If you get lots of traffic, consider:
- Moving PDFs to S3/Backblaze B2
- Serving via CloudFront/Cloudflare
- Update `pdf_service.py` to upload to cloud storage

---

## Security Checklist

Before going live:

- [ ] Use agenix for database password (not hardcoded)
- [ ] Restrict CORS to your domain (`allow_origins` in `main.py`)
- [ ] Enable HTTPS (Caddy does this automatically)
- [ ] Set up database backups
- [ ] Review firewall rules
- [ ] Add rate limiting (Caddy can do this)
- [ ] Set up monitoring/alerts
- [ ] Test error handling (try to break it!)

---

## Going Live Checklist

Final steps before launching:

- [ ] All branding updated
- [ ] Pricing calibrated with real project data
- [ ] Tested end-to-end on production server
- [ ] Database backups configured
- [ ] Monitoring set up
- [ ] DNS configured
- [ ] SSL working
- [ ] Tested on mobile devices
- [ ] Reviewed privacy policy (if collecting emails)
- [ ] Prepared for support questions

---

## Support & Updates

### Getting Help

- Check logs first (see Monitoring section)
- Review this deployment guide
- Check the main README.md
- Inspect the database for data issues

### Future Enhancements

Already architected but not implemented:
- Admin dashboard to view/manage leads
- JobTread CRM integration
- LLM-powered analysis (builder/designer insights)
- Multi-bathroom project types (kitchen, deck, etc.)
- Email automation (drip campaigns)

### Contributing Back

If you make improvements you think others would benefit from, consider:
- Documenting in the README
- Creating reusable modules
- Sharing pricing calibration strategies

---

## Quick Reference Commands

```bash
# Rebuild NixOS
sudo nixos-rebuild switch

# Restart services
systemctl restart podman-remodel-api
systemctl restart caddy

# View logs
journalctl -u podman-remodel-api -f

# Database access
psql -U remodel -d remodel

# Update frontend
rsync -avz frontend/dist/ server:/var/www/remodel-planner/

# Backup database
pg_dump -U remodel remodel > backup.sql

# Check running containers
podman ps

# Test API health
curl http://localhost:8001/health
```

---

**You're ready to deploy!** 🚀

Start with local testing, then move to production step-by-step. Don't rush - take time to customize pricing and branding before going live.

Good luck with your bathroom remodel planner! 🛁✨

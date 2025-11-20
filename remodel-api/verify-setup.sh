#!/usr/bin/env bash
#
# Verification script for Bathroom Remodel Planner
# Run this to check that all components are ready for deployment
#

set -e

echo "========================================"
echo "Remodel API Setup Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# Check function
check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "Checking required files..."
echo ""

# Backend files
test -f "Dockerfile"
check "Dockerfile exists"

test -f "requirements.txt"
check "requirements.txt exists"

test -f "app/main.py"
check "app/main.py exists"

test -f "app/database.py"
check "app/database.py exists"

test -f "app/logging_config.py"
check "app/logging_config.py exists"

test -f "app/routers/projects.py"
check "app/routers/projects.py exists"

test -f "app/routers/forms.py"
check "app/routers/forms.py exists"

test -f "app/services/pdf_service.py"
check "app/services/pdf_service.py exists"

test -f "app/engines/bathroom_cost_engine.py"
check "app/engines/bathroom_cost_engine.py exists"

test -f "app/templates/bathroom_report.html"
check "app/templates/bathroom_report.html exists"

# Config files
test -f "config/bathroom_questions.yaml"
check "config/bathroom_questions.yaml exists"

test -f "config/cost_rules_seed.sql"
check "config/cost_rules_seed.sql exists"

# Migration files
test -f "migrations/001_initial_schema.sql"
check "migrations/001_initial_schema.sql exists"

# Frontend files
test -f "frontend/package.json"
check "frontend/package.json exists"

test -f "frontend/src/App.jsx"
check "frontend/src/App.jsx exists"

test -f "frontend/src/pages/Start.jsx"
check "frontend/src/pages/Start.jsx exists"

test -f "frontend/src/pages/Results.jsx"
check "frontend/src/pages/Results.jsx exists"

test -f "frontend/src/components/Wizard.jsx"
check "frontend/src/components/Wizard.jsx exists"

test -f "frontend/src/components/Question.jsx"
check "frontend/src/components/Question.jsx exists"

# Build scripts
test -x "build-podman.sh"
check "build-podman.sh is executable"

# NixOS module
test -f "nix/container.nix"
check "nix/container.nix exists"

# Documentation
test -f "README.md"
check "README.md exists"

test -f "DEPLOYMENT.md"
check "DEPLOYMENT.md exists"

test -f "DEPLOYMENT_QUICK_START.md"
check "DEPLOYMENT_QUICK_START.md exists"

test -f "PODMAN_BUILD_GUIDE.md"
check "PODMAN_BUILD_GUIDE.md exists"

test -f "HARDENING_IMPROVEMENTS.md"
check "HARDENING_IMPROVEMENTS.md exists"

echo ""
echo "Checking Dockerfile configuration..."
echo ""

# Check Dockerfile has critical dependencies
grep -q "libcairo2" Dockerfile
check "Dockerfile includes libcairo2 (WeasyPrint dependency)"

grep -q "libpango" Dockerfile
check "Dockerfile includes libpango (WeasyPrint dependency)"

grep -q "PYTHONUNBUFFERED" Dockerfile
check "Dockerfile sets PYTHONUNBUFFERED"

grep -q "HEALTHCHECK" Dockerfile
check "Dockerfile includes health check"

echo ""
echo "Checking application configuration..."
echo ""

# Check main.py has hardening features
grep -q "lifespan" app/main.py
check "app/main.py uses lifespan context manager"

grep -q "setup_logging" app/main.py
check "app/main.py configures logging"

grep -q "exception_handler" app/main.py
check "app/main.py has global exception handler"

# Check database.py has retry logic
grep -q "max_retries" app/database.py
check "app/database.py has retry logic"

grep -q "exponential" app/database.py || grep -q "retry_delay \* attempt" app/database.py
check "app/database.py uses exponential backoff"

# Check logging_config exists and is functional
grep -q "setup_logging" app/logging_config.py
check "app/logging_config.py has setup_logging function"

echo ""
echo "========================================"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Your Bathroom Remodel Planner is ready for deployment."
    echo ""
    echo "Next steps:"
    echo "1. Review and customize pricing: config/cost_rules_seed.sql"
    echo "2. Update branding: app/templates/bathroom_report.html"
    echo "3. Build container: ./build-podman.sh"
    echo "4. Deploy to server: See DEPLOYMENT_QUICK_START.md"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS errors${NC}"
    echo ""
    echo "Please fix the issues above before deploying."
    exit 1
fi

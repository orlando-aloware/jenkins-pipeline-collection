#!/bin/bash

# Master Test Runner
# Runs all validation tests in sequence

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "========================================================================"
echo -e "${BOLD}${BLUE}Jenkins Pipeline Validation - Master Test Runner${NC}"
echo "========================================================================"
echo ""
echo "This will run all validation tests in sequence."
echo "Tests will stop at the first failure."
echo ""

# Test 1: Basic validation
echo -e "${BOLD}[1/3] Running Basic Syntax Validation...${NC}"
echo "------------------------------------------------------------------------"
if ./test-jenkinsfile.sh; then
    echo ""
    echo -e "${GREEN}✓ Basic validation passed${NC}"
else
    echo ""
    echo -e "${RED}✗ Basic validation failed${NC}"
    exit 1
fi

echo ""
echo ""

# Test 2: Advanced validation
echo -e "${BOLD}[2/3] Running Advanced Validation...${NC}"
echo "------------------------------------------------------------------------"
if python3 final-validation.py; then
    echo ""
    echo -e "${GREEN}✓ Advanced validation passed${NC}"
else
    echo ""
    echo -e "${RED}✗ Advanced validation failed${NC}"
    exit 1
fi

echo ""
echo ""

# Test 3: Docker validation (optional)
echo -e "${BOLD}[3/3] Jenkins Docker Validation (Optional)${NC}"
echo "------------------------------------------------------------------------"
echo -e "${YELLOW}Docker validation takes 60-90 seconds and requires Docker to be running.${NC}"
echo ""
read -p "Run Docker validation? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if ./test-jenkins-docker.sh; then
        echo ""
        echo -e "${GREEN}✓ Docker validation passed${NC}"
    else
        echo ""
        echo -e "${RED}✗ Docker validation failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Skipping Docker validation${NC}"
fi

echo ""
echo ""
echo "========================================================================"
echo -e "${BOLD}${GREEN}All Validation Tests Completed Successfully!${NC}"
echo "========================================================================"
echo ""
echo "Summary:"
echo "  ✅ Basic syntax validation: PASSED"
echo "  ✅ Advanced structural validation: PASSED"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  ✅ Jenkins Docker validation: PASSED"
else
    echo "  ⊘  Jenkins Docker validation: SKIPPED"
fi
echo ""
echo -e "${GREEN}${BOLD}The Jenkinsfile changes are safe to deploy!${NC}"
echo ""

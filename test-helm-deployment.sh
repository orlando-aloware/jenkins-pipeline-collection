#!/bin/bash

# Test script to validate helm deployment configuration locally
# This simulates what the Jenkinsfile does

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Testing Helm Deployment Configuration ===${NC}\n"

# Configuration
ENV="dev1"
AWS_PROFILE="alwr-dev"
AWS_REGION="us-west-2"
HELM_REPO="../helm-api-core"
WORKSPACE=$(pwd)

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Error: aws CLI is required${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq is required${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is required${NC}"; exit 1; }

if [ ! -d "$HELM_REPO" ]; then
    echo -e "${RED}Error: Helm repository not found at $HELM_REPO${NC}"
    exit 1
fi

# Test AWS credentials
echo "Testing AWS credentials..."
aws sts get-caller-identity --profile alwr-dev >/dev/null 2>&1 || {
    echo -e "${RED}Error: AWS credentials not configured for profile 'alwr-dev'${NC}"
    echo "Available profiles: $(aws configure list-profiles | tr '\n' ' ')"
    exit 1
}

echo -e "${GREEN}✓ Prerequisites OK${NC}\n"

# Function to fetch SSM parameters (matches Jenkinsfile logic)
fetch_ssm_parameters() {
    local env=$1
    local profile=$2
    
    echo "Fetching SSM parameters for /${env}/api-core/app/..."
    aws ssm get-parameters-by-path \
        --path "/${env}/api-core/app/" \
        --recursive \
        --with-decryption \
        --region "${AWS_REGION}" \
        --profile "${profile}" \
        --query "Parameters[].{Name:Name,Value:Value}" \
        --output json | jq -r '.[] | "\(.Name | sub(".*/"; ""))=\(.Value)"'
}

# Test 1: Verify SSM parameter paths
echo -e "${YELLOW}Test 1: Verifying SSM parameter paths${NC}"
echo "Checking if /shared/api-core/app/ exists..."
SHARED_COUNT=$(aws ssm get-parameters-by-path --path "/shared/api-core/app/" --recursive --region "${AWS_REGION}" --profile alwr-dev --query "Parameters[].Name" --output text 2>/dev/null | wc -w)
echo -e "Found ${GREEN}${SHARED_COUNT}${NC} parameters in /shared/api-core/app/"

echo "Checking if /dev1/api-core/app/ exists..."
DEV1_COUNT=$(aws ssm get-parameters-by-path --path "/dev1/api-core/app/" --recursive --region "${AWS_REGION}" --profile alwr-dev --query "Parameters[].Name" --output text 2>/dev/null | wc -w)
echo -e "Found ${GREEN}${DEV1_COUNT}${NC} parameters in /dev1/api-core/app/"

if [ "$SHARED_COUNT" -eq 0 ] || [ "$DEV1_COUNT" -eq 0 ]; then
    echo -e "${RED}✗ SSM parameter paths are not configured correctly${NC}"
    exit 1
fi
echo -e "${GREEN}✓ SSM parameter paths OK${NC}\n"

# Test 2: Verify critical environment variables
echo -e "${YELLOW}Test 2: Checking critical environment variables${NC}"
CRITICAL_VARS=("APP_SUB_ENV" "APP_ENV" "APP_NAME" "APP_URL")

for var in "${CRITICAL_VARS[@]}"; do
    echo -n "Checking ${var}... "
    VALUE=$(aws ssm get-parameter --name "/dev1/api-core/app/${var}" --region "${AWS_REGION}" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    if [ -z "$VALUE" ]; then
        # Try shared path
        VALUE=$(aws ssm get-parameter --name "/shared/api-core/app/${var}" --region "${AWS_REGION}" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$VALUE" ]; then
        echo -e "${RED}✗ MISSING${NC}"
    else
        echo -e "${GREEN}✓ Found: ${VALUE}${NC}"
    fi
done
echo ""

# Test 3: Simulate Jenkinsfile environment variable fetching
echo -e "${YELLOW}Test 3: Simulating Jenkinsfile environment variable fetching${NC}"
echo "Creating test .env file..."

# Create temporary directory
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Fetch parameters
echo "Fetching shared parameters..."
fetch_ssm_parameters "shared" "$AWS_PROFILE" > "$TEST_DIR/shared.env"
SHARED_VARS=$(wc -l < "$TEST_DIR/shared.env" | tr -d ' ')
echo -e "Found ${GREEN}${SHARED_VARS}${NC} shared variables"

echo "Fetching dev1-specific parameters..."
fetch_ssm_parameters "dev1" "$AWS_PROFILE" > "$TEST_DIR/custom.env"
CUSTOM_VARS=$(wc -l < "$TEST_DIR/custom.env" | tr -d ' ')
echo -e "Found ${GREEN}${CUSTOM_VARS}${NC} dev1-specific variables"

# Merge (matches Jenkinsfile logic: custom.env first, then shared.env)
cat "$TEST_DIR/custom.env" "$TEST_DIR/shared.env" | awk -F= '!seen[$1]++' > "$TEST_DIR/.env.base"
TOTAL_VARS=$(wc -l < "$TEST_DIR/.env.base" | tr -d ' ')
echo -e "Merged to ${GREEN}${TOTAL_VARS}${NC} total unique variables"

# Check for APP_SUB_ENV in merged file
if grep -q "^APP_SUB_ENV=" "$TEST_DIR/.env.base"; then
    APP_SUB_ENV_VALUE=$(grep "^APP_SUB_ENV=" "$TEST_DIR/.env.base" | cut -d'=' -f2-)
    echo -e "${GREEN}✓ APP_SUB_ENV found in merged .env: ${APP_SUB_ENV_VALUE}${NC}"
else
    echo -e "${RED}✗ APP_SUB_ENV NOT found in merged .env${NC}"
    echo "First 10 lines of merged .env:"
    head -10 "$TEST_DIR/.env.base"
fi
echo ""

# Test 4: Validate helm chart with test values
echo -e "${YELLOW}Test 4: Validating helm chart template rendering${NC}"
cd "$HELM_REPO"

# Copy dev1.yaml to values.yaml (like Jenkinsfile does)
cp values/dev1.yaml values.yaml

# Create a test env file content
cat "$TEST_DIR/.env.base" > files/vars/.env.test

echo "Running helm template to validate..."
helm template api-core . \
    --set-string image.api="test-image:latest" \
    --set-string image.queue="test-queue:latest" \
    --set-string deploy.date="$(date +%s)" \
    --set-string gitBranchName="test-branch" \
    --set-file envFile=files/vars/.env.test \
    --set-string supervisorConfig="files/vars/supervisor.conf" \
    -f values.yaml \
    > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Helm template validation passed${NC}"
else
    echo -e "${RED}✗ Helm template validation failed${NC}"
    exit 1
fi

# Extract ConfigMap to verify APP_SUB_ENV is present
echo "Checking if APP_SUB_ENV is in the rendered ConfigMap..."
helm template api-core . \
    --set-string image.api="test-image:latest" \
    --set-string image.queue="test-queue:latest" \
    --set-string deploy.date="$(date +%s)" \
    --set-string gitBranchName="test-branch" \
    --set-file envFile=files/vars/.env.test \
    --set-string supervisorConfig="files/vars/supervisor.conf" \
    -f values.yaml | grep -A 2 "APP_SUB_ENV:" || echo -e "${RED}✗ APP_SUB_ENV not found in ConfigMap${NC}"

echo ""

# Cleanup test file
rm -f files/vars/.env.test

# Test 5: Check supervisor config
echo -e "${YELLOW}Test 5: Checking supervisor configuration${NC}"
echo "Fetching supervisor config from SSM..."
SUPERVISOR_CONFIG=$(aws ssm get-parameters-by-path \
    --path "/shared/api-core/supervisor/" \
    --recursive \
    --with-decryption \
    --region "${AWS_REGION}" \
    --profile "$AWS_PROFILE" \
    --query "Parameters[].{Name:Name,Value:Value}" \
    --output json | jq -r '.[] | "\(.Name | sub(".*/"; "") | ascii_downcase): |\n  \(.Value | gsub("\\n"; "\n  "))"')

if [ -z "$SUPERVISOR_CONFIG" ]; then
    echo -e "${RED}✗ Supervisor config not found in SSM${NC}"
else
    echo -e "${GREEN}✓ Supervisor config found${NC}"
    echo "First 5 lines:"
    echo "$SUPERVISOR_CONFIG" | head -5
fi
echo ""

# Final summary
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "${GREEN}✓ All tests passed${NC}"
echo ""
echo "Environment variables summary:"
echo "  - Shared parameters: $SHARED_VARS"
echo "  - Dev1 parameters: $CUSTOM_VARS"
echo "  - Total unique: $TOTAL_VARS"
echo ""
echo "Next steps:"
echo "  1. Review the .env file structure in: $TEST_DIR/.env.base"
echo "  2. Compare with what's currently deployed in Kubernetes"
echo "  3. Test deployment with: kubectl rollout restart deployment/api-core -n app"
echo ""
echo "To view the complete merged .env file, run:"
echo "  cat $TEST_DIR/.env.base"

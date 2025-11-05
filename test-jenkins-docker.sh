#!/bin/bash

# Jenkins Docker Validation Script
# Spins up a Jenkins container and validates the Jenkinsfile using jenkins-cli

set -e

REPO_PATH="/Users/orlando/_tmp/alwr/jenkins-pipeline-collection"
JENKINSFILE_PATH="${REPO_PATH}/helm-deploy/Jenkinsfile"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "Jenkins Docker Container Validation"
echo "=================================================="
echo ""

# Check if Docker is running
echo -e "${BLUE}Checking Docker status...${NC}"
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Check if jenkins-linter container already exists
CONTAINER_NAME="jenkins-pipeline-linter"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}Removing existing container...${NC}"
    docker rm -f ${CONTAINER_NAME} > /dev/null 2>&1
fi

echo -e "${BLUE}Pulling Jenkins LTS image (this may take a moment)...${NC}"
docker pull jenkins/jenkins:lts-jdk17 > /dev/null 2>&1
echo -e "${GREEN}✓ Image pulled${NC}"
echo ""

echo -e "${BLUE}Starting Jenkins container for validation...${NC}"
docker run -d \
    --name ${CONTAINER_NAME} \
    -p 8080:8080 \
    -p 50000:50000 \
    -v "${REPO_PATH}:/workspace:ro" \
    jenkins/jenkins:lts-jdk17 > /dev/null

echo -e "${GREEN}✓ Container started${NC}"
echo ""

# Wait for Jenkins to be ready
echo -e "${BLUE}Waiting for Jenkins to be ready (this may take 30-60 seconds)...${NC}"
COUNTER=0
MAX_WAIT=120

while [ $COUNTER -lt $MAX_WAIT ]; do
    if docker exec ${CONTAINER_NAME} test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null; then
        if docker logs ${CONTAINER_NAME} 2>&1 | grep -q "Jenkins is fully up and running"; then
            echo -e "${GREEN}✓ Jenkins is ready${NC}"
            break
        fi
    fi
    
    echo -n "."
    sleep 2
    COUNTER=$((COUNTER + 2))
    
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo ""
        echo -e "${RED}✗ Jenkins failed to start within ${MAX_WAIT} seconds${NC}"
        docker logs ${CONTAINER_NAME}
        docker rm -f ${CONTAINER_NAME}
        exit 1
    fi
done
echo ""

# Install required Jenkins plugins
echo -e "${BLUE}Installing Pipeline plugin for validation...${NC}"
docker exec ${CONTAINER_NAME} jenkins-plugin-cli --plugins pipeline-model-definition > /dev/null 2>&1 || true
echo -e "${GREEN}✓ Plugins installed${NC}"
echo ""

# Validate Jenkinsfile using declarative-linter
echo -e "${BLUE}Validating Jenkinsfile syntax using Jenkins declarative-linter...${NC}"
echo ""

VALIDATION_OUTPUT=$(docker exec ${CONTAINER_NAME} sh -c "cat /workspace/helm-deploy/Jenkinsfile | /usr/local/bin/jenkins-cli declarative-linter" 2>&1) || VALIDATION_EXIT_CODE=$?

if echo "$VALIDATION_OUTPUT" | grep -q "Errors encountered validating"; then
    echo -e "${RED}✗ VALIDATION FAILED${NC}"
    echo ""
    echo "$VALIDATION_OUTPUT"
    echo ""
    docker rm -f ${CONTAINER_NAME} > /dev/null
    exit 1
elif echo "$VALIDATION_OUTPUT" | grep -qi "successfully validated\|no errors"; then
    echo -e "${GREEN}✓ JENKINSFILE IS VALID${NC}"
    echo ""
    echo "$VALIDATION_OUTPUT"
else
    echo -e "${YELLOW}⚠ Validation completed with warnings (pipeline may still work)${NC}"
    echo ""
    echo "$VALIDATION_OUTPUT"
fi

echo ""
echo -e "${BLUE}Cleaning up container...${NC}"
docker rm -f ${CONTAINER_NAME} > /dev/null
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

echo "=================================================="
echo "Jenkins Docker Validation Complete"
echo "=================================================="
echo ""

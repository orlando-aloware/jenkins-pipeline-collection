#!/bin/bash

# Docker test script to validate secret from Parameter Store
# Run this after pushing the secret to SSM

echo "=== Docker Local Test for GOOGLE_SHEETS_API_PRIVATE_KEY ==="
echo ""

# Step 1: Fetch from Parameter Store
echo "Step 1: Fetching secret from AWS Parameter Store..."
KEY_VALUE=$(aws ssm get-parameter \
    --name "/dev1/api-core/app/GOOGLE_SHEETS_API_PRIVATE_KEY" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text \
    --profile dev 2>/dev/null)

if [ -z "$KEY_VALUE" ]; then
    echo "✗ Failed to fetch from Parameter Store"
    echo "  Make sure you've run: aws ssm put-parameter ... (see instructions above)"
    exit 1
fi

echo "✓ Successfully fetched from Parameter Store"
echo "  Key length: $(echo -n "$KEY_VALUE" | wc -c) bytes"
echo ""

# Step 2: Start Docker container
echo "Step 2: Starting Docker container..."
docker run -d \
    --name test-secret-validation \
    -e GOOGLE_SHEETS_API_PRIVATE_KEY="$KEY_VALUE" \
    alpine:latest \
    sleep 300 > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "✗ Failed to start Docker container"
    docker rm -f test-secret-validation 2>/dev/null
    exit 1
fi

echo "✓ Docker container started"
echo ""

# Step 3: Install openssl in container and test
echo "Step 3: Testing key validation in Docker container..."
docker exec test-secret-validation sh -c '
    apk add --no-cache openssl
    echo "$GOOGLE_SHEETS_API_PRIVATE_KEY" > /tmp/test_key.pem
    
    echo "Key file size: $(wc -c < /tmp/test_key.pem) bytes"
    echo ""
    
    echo "Key validation with openssl:"
    openssl pkey -in /tmp/test_key.pem -check -noout
    KEY_CHECK=$?
    
    if [ $KEY_CHECK -eq 0 ]; then
        echo "✓ Key is VALID"
    else
        echo "✗ Key is INVALID (exit code: $KEY_CHECK)"
    fi
    
    echo ""
    echo "ASN.1 structure check:"
    openssl asn1parse -in /tmp/test_key.pem > /dev/null 2>&1
    ASN_CHECK=$?
    if [ $ASN_CHECK -eq 0 ]; then
        echo "✓ ASN.1 structure is valid"
    else
        echo "✗ ASN.1 parsing failed"
    fi
    
    echo ""
    echo "Key info (first 20 lines):"
    openssl pkey -in /tmp/test_key.pem -text -noout | head -20
' 2>&1

# Step 4: Cleanup
echo ""
echo "Step 4: Cleaning up Docker container..."
docker rm -f test-secret-validation > /dev/null 2>&1
echo "✓ Container removed"

echo ""
echo "=== Test Complete ==="

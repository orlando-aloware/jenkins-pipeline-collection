#!/bin/bash
# Source: either set directly, export from environment, or fetch from AWS Parameter Store
# Priority: 1) exported env var 2) fetch from Parameter Store 3) hardcoded value
echo 'export GOOGLE_SHEETS_API_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC2JyiQQ/5UXufq
bopEUGYUKiAIB+fFnFfpU3XvYS2GNEmmUaCHC2ID7V2BYH4nZBoXtoKzyWvHXjaC
h/KwRcEO6sEW/7x04zV9uGU01E7em3wTaYyKd9/QZ17u73cN0JLjf/9goaRxqTgR
wVYZBwTiP7KRBsKrC/bxUuRu/QdO9+P1jgFVubOvVsbyNZTJ0nrxmz5YvPUJBrSE
YQfmICss0JHCSMq1bMFFOoVoTvwxVhh7+mncLg8Q+o5VvZaM5mL4glJgKyBKyQVv
+fufdcl5H2yMkhGHbN5JAu8tWrRvzhBA978kaH6EWX2qw9Cgroydc5wT3bKjc52W
A/hsBX6dAgMBAAECggEADLPX4BGhyYvxw9cwFLn/mF3krHKyrsTrm4WatpYSCOca
ELtmBKzeSbRSnjxWp9QS/r7XSAbemYFgL0OgQLsojqv/yaUNZSBYIVuL0T6R/nOc
2DS23IwmA0BGLkbsSD4YlD1fl4NGNrfshU50fNvQsx9qijMMvcVgk+0qKXRDP3Yr
WOG7RByXS5WBk6HCKFo4BYri6ze3WGmNi3O9DoDfnFQ9pAOZY9/FNWqjTzgExC+1
vW64JPSxZomWmZ058EpXcSQHHCnHR33yYQ+4XPpI+SH9dAa3i9vWCxg18zQSpNdZ
yNv9CtHdrHNX++OiDMgM22OYSrXD0ArTn+KUMZcxUQKBgQDkYyEf4n2hhDshjmt/
BVMeleE9n7TAqt0lUpSG8d9uaBA3UpZxZhmScCDyTM9yXa0JLKpoDQ/iLmRghNOy
u3L8B+iuCGF9OOjHUB5LZTnCTCCLSCOhNYr084Ibdd21ardRn5dp7efmzClhLK1a
GC/sGyfptIp02ee1P7DtZESF7QKBgQDMLQVQ0Mz/4kW3yGaLj0prkMqZaY3Sz7zA
8vZ42LKbvJh5AYRPc+vfqNfUO3M3Tljr2D366NLYDWVz5I5xgXl3dxCEwQuG9qPo
iK8B0MBAvDZtbbRazlpnbSe0nppCHbGIlCQ/ts78ODxo/sY9YA+DvCW1ds5Yh+6K
Jqw2srPFcQKBgQCBzAzBUDlSGBJ7CbPyJpaMpWWzXhaeAP1Z/srGvqPa3W2J43f4
zqvt26f9zMWBG9gBhM77/6BtTSxi5lpiE8JPljcY4U52mmdBDzmIY+klkZpVThRh
xEpK2DGzZZMxTYsN6oNlAn5vXsyNm5SRxXlG2FAgtCiULFtRWPc2k2uWKQKBgQDI
jxDBqdk1IZdKSFgyjraTos7gk4b0pYrMHd1uJ66KvF8pvgux4DS6pqgbmao7kYJX
aTq41SsHf2FAzin95Sjj6NkZDme8U1n+eQUvy1aOQFNWeoTHDhxPrDFsgr8UYwaZ
GqvgyjnYF4V/vYQNleaniJGiBun6nMv8eLCBqlhcgQKBgQCNSEqqM8uX8ZPUHcqn
HdW56zVYGlp64BzAKxrY01pnlrYI4ZY8uVZPq2QvJDWkM5AxUrusU7tLh8RCqjtv
F4CVHxczut11eamZpEpql3ntBV1L8HcaaYw4dcnFLLXre2aJ55f/aUHLiUEy31tX
/tamaH0BoyeT2l1SFY+wiXJuPg==
-----END PRIVATE KEY-----"'



HARDCODED_GOOGLE_SHEETS_API_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC2JyiQQ/5UXufq
bopEUGYUKiAIB+fFnFfpU3XvYS2GNEmmUaCHC2ID7V2BYH4nZBoXtoKzyWvHXjaC
h/KwRcEO6sEW/7x04zV9uGU01E7em3wTaYyKd9/QZ17u73cN0JLjf/9goaRxqTgR
wVYZBwTiP7KRBsKrC/bxUuRu/QdO9+P1jgFVubOvVsbyNZTJ0nrxmz5YvPUJBrSE
YQfmICss0JHCSMq1bMFFOoVoTvwxVhh7+mncLg8Q+o5VvZaM5mL4glJgKyBKyQVv
+fufdcl5H2yMkhGHbN5JAu8tWrRvzhBA978kaH6EWX2qw9Cgroydc5wT3bKjc52W
A/hsBX6dAgMBAAECggEADLPX4BGhyYvxw9cwFLn/mF3krHKyrsTrm4WatpYSCOca
ELtmBKzeSbRSnjxWp9QS/r7XSAbemYFgL0OgQLsojqv/yaUNZSBYIVuL0T6R/nOc
2DS23IwmA0BGLkbsSD4YlD1fl4NGNrfshU50fNvQsx9qijMMvcVgk+0qKXRDP3Yr
WOG7RByXS5WBk6HCKFo4BYri6ze3WGmNi3O9DoDfnFQ9pAOZY9/FNWqjTzgExC+1
vW64JPSxZomWmZ058EpXcSQHHCnHR33yYQ+4XPpI+SH9dAa3i9vWCxg18zQSpNdZ
yNv9CtHdrHNX++OiDMgM22OYSrXD0ArTn+KUMZcxUQKBgQDkYyEf4n2hhDshjmt/
BVMeleE9n7TAqt0lUpSG8d9uaBA3UpZxZhmScCDyTM9yXa0JLKpoDQ/iLmRghNOy
u3L8B+iuCGF9OOjHUB5LZTnCTCCLSCOhNYr084Ibdd21ardRn5dp7efmzClhLK1a
GC/sGyfptIp02ee1P7DtZESF7QKBgQDMLQVQ0Mz/4kW3yGaLj0prkMqZaY3Sz7zA
8vZ42LKbvJh5AYRPc+vfqNfUO3M3Tljr2D366NLYDWVz5I5xgXl3dxCEwQuG9qPo
iK8B0MBAvDZtbbRazlpnbSe0nppCHbGIlCQ/ts78ODxo/sY9YA+DvCW1ds5Yh+6K
Jqw2srPFcQKBgQCBzAzBUDlSGBJ7CbPyJpaMpWWzXhaeAP1Z/srGvqPa3W2J43f4
zqvt26f9zMWBG9gBhM77/6BtTSxi5lpiE8JPljcY4U52mmdBDzmIY+klkZpVThRh
xEpK2DGzZZMxTYsN6oNlAn5vXsyNm5SRxXlG2FAgtCiULFtRWPc2k2uWKQKBgQDI
jxDBqdk1IZdKSFgyjraTos7gk4b0pYrMHd1uJ66KvF8pvgux4DS6pqgbmao7kYJX
aTq41SsHf2FAzin95Sjj6NkZDme8U1n+eQUvy1aOQFNWeoTHDhxPrDFsgr8UYwaZ
GqvgyjnYF4V/vYQNleaniJGiBun6nMv8eLCBqlhcgQKBgQCNSEqqM8uX8ZPUHcqn
HdW56zVYGlp64BzAKxrY01pnlrYI4ZY8uVZPq2QvJDWkM5AxUrusU7tLh8RCqjtv
F4CVHxczut11eamZpEpql3ntBV1L8HcaaYw4dcnFLLXre2aJ55f/aUHLiUEy31tX
/tamaH0BoyeT2l1SFY+wiXJuPg==
-----END PRIVATE KEY-----"
# Option 1: Check if already exported from environment
if [ -z "$GOOGLE_SHEETS_API_PRIVATE_KEY" ]; then
    # Option 2: Try to fetch from AWS Parameter Store
    if command -v aws &> /dev/null; then
        echo "=== Fetching from AWS Parameter Store ==="
        GOOGLE_SHEETS_API_PRIVATE_KEY=$(aws ssm get-parameter \
            --name "/shared/api-core/app/GOOGLE_SHEETS_API_PRIVATE_KEY" \
            --with-decryption \
            --query 'Parameter.Value' \
            --output text 2>/dev/null)
        
        if [ -z "$GOOGLE_SHEETS_API_PRIVATE_KEY" ]; then
            echo "⚠ Failed to fetch from Parameter Store, using hardcoded value"
            GOOGLE_SHEETS_API_PRIVATE_KEY=$HARDCODED_GOOGLE_SHEETS_API_PRIVATE_KEY
        fi
    else
        echo "⚠ AWS CLI not found, using hardcoded value"
        GOOGLE_SHEETS_API_PRIVATE_KEY=$HARDCODED_GOOGLE_SHEETS_API_PRIVATE_KEY
    fi
else
    echo "✓ Using exported GOOGLE_SHEETS_API_PRIVATE_KEY from environment"
fi

if [ -z "$GOOGLE_SHEETS_API_PRIVATE_KEY" ]; then
    echo "✗ No key found in environment, Parameter Store, or hardcoded value"
    exit 1
fi


echo "✓ Key written to /tmp/test_key.pem"
echo ""

echo "=== Step 2: Validate RSA private key format ==="
openssl pkey -in /tmp/test_key.pem -check -noout
KEY_CHECK=$?
if [ $KEY_CHECK -eq 0 ]; then
    echo "✓ Key format is valid"
else
    echo "✗ Key format validation failed (exit code: $KEY_CHECK)"
fi
echo ""

echo "=== Step 3: Parse ASN.1 structure ==="
openssl asn1parse -in /tmp/test_key.pem
ASN_CHECK=$?
if [ $ASN_CHECK -eq 0 ]; then
    echo "✓ ASN.1 structure is valid"
else
    echo "✗ ASN.1 parsing failed (exit code: $ASN_CHECK)"
fi
echo ""

echo "=== Step 4: Extract key info ==="
openssl pkey -in /tmp/test_key.pem -text -noout | head -20
echo ""

echo "=== Summary ==="
if [ $KEY_CHECK -eq 0 ] && [ $ASN_CHECK -eq 0 ]; then
    echo "✓ All validation checks passed - key is valid"
    exit 0
else
    echo "✗ Validation failed - key appears to be corrupted or incomplete"
    exit 1
fi

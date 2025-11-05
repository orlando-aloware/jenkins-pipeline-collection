pipeline {
    agent any

    environment {
        AWS_REGION = 'us-west-2'
        // AWS credentials should be configured via Jenkins credentials or AWS CLI profile
        // AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        // AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
    }

    stages {
        stage('Test fetchSSMParameters') {
            steps {
                script {
                    // Mimic the production pipeline call - just like in Setup Files stage
                    echo "=== Testing fetchSSMParameters function ==="
                    
                    // Test with 'shared' environment (same as production)
                    // Function signature: fetchSSMParameters(String app, String env, String profile)
                    def sharedVars = fetchSSMParameters("api-core", "shared", "default")
                    
                    echo "=== Shared Variables Output ==="
                    echo "================================"
                    
                    // Write to file to inspect
                    writeFile file: 'shared.env', text: sharedVars + '\n'

                    def sharedEnv1Vars = sharedVars

                    // Print all shared environment variables
                    echo "=== Shared Environment Variables ==="
                    def sharedLines = sharedEnv1Vars.split('\n')
                    echo "Total shared variables found: ${sharedLines.size()}"
                    echo ""
                    echo sharedEnv1Vars
                    echo "==================================="
                    echo ""
                    
                    // Show the GOOGLE_SHEETS_API_PRIVATE_KEY specifically
                    sh '''
                        echo "=== Extracting GOOGLE_SHEETS_API_PRIVATE_KEY ==="
                        grep "GOOGLE_SHEETS_API_PRIVATE_KEY" shared.env || echo "Key not found"
                        
                        echo ""
                        echo "=== Checking for escaped newlines (\\n) ==="
                        if grep "GOOGLE_SHEETS_API_PRIVATE_KEY" shared.env | grep -q '\\\\n'; then
                            echo "❌ FOUND ESCAPED NEWLINES - This is the bug!"
                            echo "Count of \\\\n sequences:"
                            grep "GOOGLE_SHEETS_API_PRIVATE_KEY" shared.env | grep -o '\\\\n' | wc -l
                        else
                            echo "✓ No escaped newlines found"
                        fi
                        
                        echo ""
                        echo "=== Checking for literal newlines ==="
                        if grep -Pzo "GOOGLE_SHEETS_API_PRIVATE_KEY=.*\\n.*\\n" shared.env > /dev/null 2>&1; then
                            echo "✓ FOUND LITERAL NEWLINES - This is correct!"
                        else
                            echo "❌ No literal newlines - key is on one line"
                        fi
                    '''
                }
            }
        }
    }
}

// Function to fetch parameters from SSM
def fetchSSMParameters(String app, String env, String profile) {
    return sh(script: """
        aws ssm get-parameters-by-path \\
        --path "/${env}/${app}/app/" \\
        --recursive \\
        --with-decryption \\
        --profile "${profile}" \\
        --query "Parameters[].{Name:Name,Value:Value}" \\
        --output json | jq -r '.[] | "\\(.Name | sub(".*/"; ""))=\\(.Value)"'
    """, returnStdout: true).trim()
}

// Function to fetch parameters from SSM
def fetchSSMParameters_Old(String app, String env, String profile) {
    return sh(script: """
        aws ssm get-parameters-by-path \\
        --path "/${env}/${app}/app/" \\
        --recursive \\
        --with-decryption \\
        --profile "${profile}" \\
        --query "Parameters[].{Name:Name,Value:Value}" \\
        --output json | jq -r '.[] | "\\(.Name | sub(".*/"; ""))=\\"\\(.Value)\\""'
    """, returnStdout: true).trim()
}
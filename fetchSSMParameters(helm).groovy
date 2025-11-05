def fetchSSMParameters(String env, String profile) {
    return sh(script: """
        export AWS_SHARED_CREDENTIALS_FILE='${AWS_CREDS}'
        aws ssm get-parameters-by-path \\
        --path "/${env}/api-core/app/" \\
        --recursive \\
        --with-decryption \\
        --profile "${profile}" \\
        --query "Parameters[].{Name:Name,Value:Value}" \\
        --output json | jq -r '.[] | "\\(.Name | sub(".*/"; ""))=\\(.Value)"'
    """, returnStdout: true).trim()
}
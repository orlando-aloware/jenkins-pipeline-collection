def executeCommand(List<String> command) {
    def process = command.execute()
    def stdout = new StringBuilder()
    def stderr = new StringBuilder()
    process.waitForProcessOutput(stdout, stderr)
    if (stderr) {
        System.err.print(stderr.toString())
    }
    stdout.toString().trim()
}

def fetchSSMParameters(String env, String profile) {
    def awsOutput = executeCommand([
        'aws', 'ssm', 'get-parameters-by-path',
        '--path', "/${env}/api-core/app/",
        '--recursive',
        '--with-decryption',
        '--region', 'us-west-2',
        '--query', 'Parameters[].{Name:Name,Value:Value}',
        '--output', 'json'
    ])

    if (!awsOutput) {
        return ''
    }

    def jqFilter = $/.[] | select(.Value != null) | (.Name | sub(".*/"; "")) + "=" + @sh "\(.Value)"/$

    def jqProcess = ['jq', '-r', jqFilter].execute()
    jqProcess.withWriter { it << awsOutput }

    def result = new StringBuilder()
    def jqErr = new StringBuilder()
    jqProcess.waitForProcessOutput(result, jqErr)
    if (jqErr) {
        System.err.print(jqErr.toString())
    }
    result.toString().trim()
}

println 'Testing fetchSSMParameters...'
println '----------------------------------------'
println fetchSSMParameters('shared', 'default')
println '----------------------------------------'

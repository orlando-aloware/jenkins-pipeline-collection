@Library('jenkins-shared-libraries') _

pipeline {
    agent any
    parameters {
        string(name: 'BRANCH_NAME', defaultValue: 'develop', description: 'Git Repository Branch')
        choice(name: 'ENV', choices: ['dev1', 'mde', 'staging'], description: 'Name of the environment where the deployment will be performed')
    }
    environment {
        GH_APP_ID = '1157885'
        GH_INSTALLATION_ID = '61798182'
        GITHUB_ORG = 'aloware'
        HELM_REPO = 'helm-api-core'
        API_CORE_REPO = 'api-core'
        BASE_PHP_IMAGE = 'aloware-base-images/php-fpm:latest'
        BASE_RUNNER_USER = 'ubuntu'
        WWW_DATA_ID = '82'
        // Base image settings
        BASE_IMAGE_REGISTRY = '333629833033.dkr.ecr.us-west-2.amazonaws.com'
        // Dev environment settings
        DEV_MDE_EKS_CLUSTER_NAME = 'aloware-dev-uswest2-eks-cluster-cr-01'
        DEV_MDE_ECR_REGISTRY = '333629833033.dkr.ecr.us-west-2.amazonaws.com'
        MDE_DATABASE_HOST = "aloware-dev-mde-shared-rds-cr.cluster-cempo0wxi0u3.us-west-2.rds.amazonaws.com"
        // Staging environment settings
        STAGING_EKS_CLUSTER_NAME = 'aloware-eks-staging'
        STAGING_ECR_REGISTRY = '225989345843.dkr.ecr.us-west-2.amazonaws.com'
        // Common settings
        AWS_REGION = 'us-west-2'
        ECR_REPO = 'api-core'
        MDE_DATABASE_PASSWORD = credentials('mde_database_password')
        MDE_DATABASE_USERNAME = 'admin'
        STAGING_EKS_ADMIN_ROLE_ARN = 'arn:aws:iam::225989345843:role/alwr-eks-admin-role-staging'
       
    }
    stages {
        stage('Prepare Environment') {
            steps {  
                script {
                    env.TOKEN = getGitHubAppToken()
                    
                    // Set custom build description
                    def buildUser = 'System'
                    def userCause = currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause')
                    if (userCause) {
                        buildUser = userCause[0].userId
                    }
                    currentBuild.description = "server: ${params.ENV} / branch: ${params.BRANCH_NAME} / by: ${buildUser}"
                    
                    // Validate that staging environment can only be used with develop or release branch
                    if (params.ENV == 'staging' && params.BRANCH_NAME != 'develop' && params.BRANCH_NAME != 'release') {
                        error "Staging environment can only be used with the develop or release branch. Please use develop or release branch for staging deployments. Pipeline will be aborted."
                    }
                    
                    if (params.BRANCH_NAME != 'develop') {
                        try {
                            def prId = sh(script: """
                                curl -s -X GET \
                                -H "Authorization: token ${TOKEN}" \
                                -H "Accept: application/vnd.github+json" \
                                "https://api.github.com/repos/${GITHUB_ORG}/${API_CORE_REPO}/pulls?head=${GITHUB_ORG}:${params.BRANCH_NAME}&state=open" | \
                                jq -r '.[0].number // "null"'
                            """, returnStdout: true).trim()
                            
                            if (prId == "null" || prId == "") {
                                error "No open PR associated with branch ${params.BRANCH_NAME} was found. Pipeline will be aborted."
                            }

                            env.PR_ID = "pr-${prId}"
                            env.PR_NUMBER = prId

                            switch(params.ENV) {
                                case 'mde':
                                    env.NAMESPACE = "pr-${prId}"
                                    env.AWS_PROFILE = 'dev'
                                    env.EKS_CLUSTER_NAME = env.DEV_MDE_EKS_CLUSTER_NAME
                                    env.ECR_REGISTRY = env.DEV_MDE_ECR_REGISTRY
                                    env.EXTRA_ARGS = ''
                                    break
                                case 'dev1':
                                    env.NAMESPACE = 'app'
                                    env.AWS_PROFILE = 'dev'
                                    env.EKS_CLUSTER_NAME = env.DEV_MDE_EKS_CLUSTER_NAME
                                    env.ECR_REGISTRY = env.DEV_MDE_ECR_REGISTRY
                                    env.EXTRA_ARGS = ''
                                    break
                                case 'staging':
                                    env.NAMESPACE = 'app'
                                    env.AWS_PROFILE = 'staging'
                                    env.EKS_CLUSTER_NAME = env.STAGING_EKS_CLUSTER_NAME
                                    env.ECR_REGISTRY = env.STAGING_ECR_REGISTRY
                                    env.EXTRA_ARGS = "--role-arn ${STAGING_EKS_ADMIN_ROLE_ARN}"
                                    break
                            }

                        } catch (Exception e) {
                            echo "Error fetching PR associated with branch: ${e.getMessage()}"
                            error "Failed to retrieve PR information. Pipeline will be aborted."
                        }
                    } else {
                        if (params.ENV == 'mde') {
                            error "Do not use an MDE to test the develop branch. Pipeline will be aborted."
                        } else {
                            switch(params.ENV) {
                                case 'dev1':
                                    env.NAMESPACE = 'app'
                                    env.AWS_PROFILE = 'dev'
                                    env.EKS_CLUSTER_NAME = env.DEV_MDE_EKS_CLUSTER_NAME
                                    env.ECR_REGISTRY = env.DEV_MDE_ECR_REGISTRY
                                    env.EXTRA_ARGS = ''
                                    break
                                case 'staging':
                                    env.NAMESPACE = 'app'
                                    env.AWS_PROFILE = 'staging'
                                    env.EKS_CLUSTER_NAME = env.STAGING_EKS_CLUSTER_NAME
                                    env.ECR_REGISTRY = env.STAGING_ECR_REGISTRY
                                    env.EXTRA_ARGS = '--role-arn arn:aws:iam::225989345843:role/alwr-eks-admin-role-staging'
                                    break
                            }
                        }
                    }

                    if (params.ENV == 'mde') {
                        def namespaces = sh(script: 'kubectl get namespaces | grep -i pr-* | wc -l', returnStdout: true)
                            .trim().toInteger()
                        def currentNamespace = sh(
                            script: "kubectl get namespaces | grep -i ${BRANCH_NAME} | wc -l", returnStdout: true
                        ).trim().toInteger()

                        if (namespaces >= 10 && currentNamespace == 0) {
                            error "Currently we have ${namespaces} MDE namespaces and this is the limit. Pipeline will be aborted."
                        }
                    }
                    
                    // Configure AWS credentials for different accounts
                    withCredentials([file(credentialsId: 'aws-credentials-profiles', variable: 'AWS_CREDS')]) {
                        sh """
                            export AWS_SHARED_CREDENTIALS_FILE='${AWS_CREDS}'
                            
                            # Update EKS kubeconfig using the appropriate profile
                            aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME} --profile ${AWS_PROFILE} --alias ${EKS_CLUSTER_NAME} ${EXTRA_ARGS}
                            
                            # Login to ECRs
                            aws ecr get-login-password --region ${AWS_REGION} --profile dev | docker login --username AWS --password-stdin ${DEV_MDE_ECR_REGISTRY}
                            aws ecr get-login-password --region ${AWS_REGION} --profile staging | docker login --username AWS --password-stdin ${STAGING_ECR_REGISTRY}
                        """
                    }
                    
                    wrap([$class: 'MaskPasswordsBuildWrapper', varPasswordPairs: [[password: TOKEN, var: 'TOKEN']]]) {
                        // Configure git for optimal performance
                        sh """
                            git config --global core.preloadindex true
                            git config --global core.fscache true
                            git config --global gc.auto 0
                            git config --global http.postBuffer 1048576000
                            git config --global http.maxRequestBuffer 100M
                            git config --global http.lowSpeedLimit 0
                            git config --global http.lowSpeedTime 999999
                        """
                        
                        // Clone repositories in parallel with optimizations
                        parallel(
                            "Clone Helm Repo": {
                                sh """
                                    git clone \\
                                        --depth=1 \\
                                        --single-branch \\
                                        --no-tags \\
                                        --quiet \\
                                        https://x-access-token:${TOKEN}@github.com/${GITHUB_ORG}/${HELM_REPO}.git
                                """
                            },
                            "Clone API Core Repo": {
                                sh """
                                    git clone \\
                                        --depth=1 \\
                                        --single-branch \\
                                        --branch=${BRANCH_NAME} \\
                                        --no-tags \\
                                        --quiet \\
                                        https://x-access-token:${TOKEN}@github.com/${GITHUB_ORG}/${API_CORE_REPO}.git
                                """
                            }
                        )
                    }   
                }
            }
        }
        
        stage('Build Dependencies') {
            parallel {
                stage('Pull Base Image') {
                    steps {
                        script {
                            // Pre-pull the base image to avoid pulling it multiple times in parallel
                            sh "docker pull ${BASE_IMAGE_REGISTRY}/${BASE_PHP_IMAGE}"
                        }
                    }
                }
            }
        }
        
        stage('Install Dependencies') {
            parallel {
                stage('Install Composer Dependencies') {
                    steps {
                        dir("${API_CORE_REPO}") {
                            script {
                                def composer_auth = "{\"http-basic\": {\"github.com\": {\"username\": \"x-access-token\", \"password\": \"${TOKEN}\"}}}\n"
                                sh """
                                    docker run --rm \\
                                        -v \$(pwd):/app \\
                                        -w /app \\
                                        -e COMPOSER_AUTH='${composer_auth}' \\
                                        -e SSL_MODE=off \\
                                        -e AUTORUN_LARAVEL_MIGRATION=false \\
                                        -e AUTORUN_ENABLED=false \\
                                        --cpus="2" \\
                                        --memory="2g" \\
                                        --network=host \\
                                        ${BASE_IMAGE_REGISTRY}/${BASE_PHP_IMAGE} \\
                                        composer install --no-scripts --optimize-autoloader
                                """
                            }
                        }
                    }
                }
                
                stage('Install Node Dependencies and Build') {
                    steps {
                        dir("${API_CORE_REPO}") {
                            script {
                                sh """
                                    docker run --rm \\
                                        -v \$(pwd):/app \\
                                        -w /app \\
                                        -e SSL_MODE=off \\
                                        -e AUTORUN_LARAVEL_MIGRATION=false \\
                                        -e AUTORUN_ENABLED=false \\
                                        --cpus="2" \\
                                        --memory="2g" \\
                                        --network=host \\
                                        ${BASE_IMAGE_REGISTRY}/${BASE_PHP_IMAGE} \\
                                        sh -c "yarn install --pure-lockfile --network-timeout 100000 && npm run dev"
                                """
                            }
                        }
                    }
                }
            }
        }
        
        stage('Fix permissions and package dependencies') {
            steps {
                dir("${API_CORE_REPO}") {
                    script {
                        sh """
                            sudo chown -R ${WWW_DATA_ID}:${WWW_DATA_ID} .
                            sudo chown ${BASE_RUNNER_USER}:${BASE_RUNNER_USER} .

                            find . -type f -exec sudo chmod 644 {} +
                            find . -type d -exec sudo chmod 755 {} +

                            # Pre-clean dependencies to reduce image size
                            find vendor/ -name "*.md" -delete 2>/dev/null || true
                            find vendor/ -name "README*" -delete 2>/dev/null || true
                            find vendor/ -name "CHANGELOG*" -delete 2>/dev/null || true
                            find vendor/ -name "LICENSE*" -delete 2>/dev/null || true
                            find vendor/ -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
                            find vendor/ -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
                            find vendor/ -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
                            
                            find node_modules/ -name "*.md" -delete 2>/dev/null || true
                            find node_modules/ -name "README*" -delete 2>/dev/null || true
                            find node_modules/ -name "CHANGELOG*" -delete 2>/dev/null || true
                            find node_modules/ -name "LICENSE*" -delete 2>/dev/null || true
                            find node_modules/ -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
                            find node_modules/ -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
                            find node_modules/ -type d -name "__tests__" -exec rm -rf {} + 2>/dev/null || true
                            find node_modules/ -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
                            find node_modules/ -name ".cache" -exec rm -rf {} + 2>/dev/null || true

                            tar cf dependencies.tar vendor/ node_modules/
                        """
                    }
                }
            }
        }
        
        stage('Build API and QUEUE Docker Image') {
            parallel {
                stage('Build API Docker Image') {
                    steps {
                        dir("${API_CORE_REPO}") {
                            script {
                                env.ECR_API_IMAGE = "${ECR_REGISTRY}/${ECR_REPO}/api:${NAMESPACE}"
                                sh """
                                    export DOCKER_BUILDKIT=1
                                    export COMPOSE_DOCKER_CLI_BUILD=1
                                    docker buildx build \\
                                        --build-arg BUILDKIT_INLINE_CACHE=1 \\
                                        -t ${ECR_API_IMAGE} \\
                                        -f '../helm-deploy/Dockerfile-api' \\
                                        --compress \\
                                        --push \\
                                        .
                                """
                            }
                        }
                    }
                }

                stage('Build QUEUE Docker Image') {
                    steps {
                        dir("${API_CORE_REPO}") {
                            script {
                                env.ECR_QUE_IMAGE = "${ECR_REGISTRY}/${ECR_REPO}/queue:${NAMESPACE}"
                                sh """
                                    export DOCKER_BUILDKIT=1
                                    export COMPOSE_DOCKER_CLI_BUILD=1
                                    docker buildx build \\
                                        --build-arg BUILDKIT_INLINE_CACHE=1 \\
                                        -t ${ECR_QUE_IMAGE} \\
                                        -f '../helm-deploy/Dockerfile-queue' \\
                                        --compress \\
                                        --push \\
                                        .
                                """
                            }
                        }
                    }
                }
            }
        }
        
        stage('Create Mysql Database') {
            when {
                equals expected: 'mde', actual: "${params.ENV}"
            }
            steps {
                script {
                    env.MDE_DATABASE_NAME = env.PR_ID.replaceAll('-', '_')
                    
                    def result = sh(script: "mysql -h ${MDE_DATABASE_HOST} -P 3306 -u${MDE_DATABASE_USERNAME} -p${MDE_DATABASE_PASSWORD} -Nse \"SHOW DATABASES LIKE '${MDE_DATABASE_NAME}';\"", returnStdout: true).trim()

                    if (result) {
                        echo "Database already exists."
                    } else {
                        echo "Database not found. Creating..."

                        withCredentials([
                            file(credentialsId: 'aws-credentials-profiles', variable: 'AWS_CREDS'),
                            string(credentialsId: 'mde_database_password', variable: 'DB_PASSWORD')
                        ]) {
                            sh """
                                export AWS_PROFILE='dev'
                                export AWS_REGION=${AWS_REGION}
                                export AWS_SHARED_CREDENTIALS_FILE='${AWS_CREDS}'

                                aws s3 cp s3://aloware-phoenix-db/aloware-latest.sql.gz aloware-latest.sql.gz --quiet
                                gzip -d aloware-latest.sql.gz -q

                                mysql -h ${MDE_DATABASE_HOST} -P 3306 -u${MDE_DATABASE_USERNAME} -p${DB_PASSWORD} -e "CREATE DATABASE ${MDE_DATABASE_NAME};"
                                mysql -h ${MDE_DATABASE_HOST} -P 3306 -u${MDE_DATABASE_USERNAME} -p${DB_PASSWORD} ${MDE_DATABASE_NAME} < aloware-latest.sql
                                
                                mysql -h ${MDE_DATABASE_HOST} -P 3306 -u${MDE_DATABASE_USERNAME} -p${DB_PASSWORD} ${MDE_DATABASE_NAME} -e "
                                UPDATE companies
                                SET facebook_integration_enabled='0',
                                    g_calendar_integration_enabled='0',
                                    zapier_integration_enabled='0',
                                    pipedrive_integration_enabled='0',
                                    hubspot_integration_enabled='0',
                                    slack_integration_enabled='0',
                                    domo_integration_enabled='0',
                                    gohighlevel_integration_enabled='0',
                                    zoho_integration_enabled='0',
                                    guesty_integration_enabled='0',
                                    salesforce_integration_enabled='0'
                                WHERE 1;

                                TRUNCATE TABLE external_integration_map;
                                TRUNCATE TABLE integration_settings;
                                TRUNCATE TABLE integration_property_map;"

                                rm -f aloware-latest.sql*
                                rm -f aws-credentials
                            """
                        }
                        
                        echo "Database created successfully."
                    }
                }
            }
        }    

        stage('Setup Files') {
            steps {
                script {
                    // Configure AWS credentials for SSM parameter access
                    withCredentials([file(credentialsId: 'aws-credentials-profiles', variable: 'AWS_CREDS')]) {
                        sh "export AWS_SHARED_CREDENTIALS_FILE='${AWS_CREDS}'"
                        
                        // Get config files
                        def supervisorConfig = sh(script: """
                            export AWS_SHARED_CREDENTIALS_FILE='${AWS_CREDS}'
                            aws ssm get-parameters-by-path \\
                            --path "/shared/api-core/supervisor/" \\
                            --recursive \\
                            --with-decryption \\
                            --profile "${AWS_PROFILE}" \\
                            --query "Parameters[].{Name:Name,Value:Value}" \\
                            --output json | jq -r '.[] | "\\(.Name | sub(".*/"; "") | ascii_downcase): |\\n  \\(.Value | gsub("\\\\n"; "\\n  "))"'
                        """, returnStdout: true).trim()

                        writeFile file: "${env.WORKSPACE}/${env.HELM_REPO}/files/vars/supervisor.conf", text: supervisorConfig + '\n'

                        // Determine the appropriate values file based on environment
                        def valuesFileName = ""
                        switch(params.ENV) {
                            case 'dev1':
                                valuesFileName = 'values/dev1.yaml'
                                break
                            case 'staging':
                                valuesFileName = 'values/staging.yaml'
                                break
                            case 'mde':
                                valuesFileName = 'values/mde.yaml'
                                break
                        }

                        // Copy the appropriate values file to values.yaml for helm deployment
                        sh "cp ${env.WORKSPACE}/${env.HELM_REPO}/${valuesFileName} ${env.WORKSPACE}/${env.HELM_REPO}/values.yaml"
                    
                        // Get Environment Variables
                        def sharedVars = fetchSSMParameters("shared", AWS_PROFILE)
                        def specificVars = fetchSSMParameters(params.ENV, AWS_PROFILE)
                        
                        writeFile file: 'shared.env', text: sharedVars + '\n'
                        writeFile file: 'custom.env', text: specificVars + '\n'

                        sh '''
                            cat custom.env shared.env | awk -F= '!seen[$1]++' > ${HELM_REPO}/files/.env.base
                            rm shared.env custom.env
                        '''

                        if (params.ENV == 'mde') {
                            dir("${WORKSPACE}/${HELM_REPO}/files") {
                                env.APP_URL = "https://${PR_ID}.mde.alodev.org"
                                def vars = [
                                    'PROJECT': PR_ID,
                                    'DB_PASSWORD': MDE_DATABASE_PASSWORD,
                                    'DB_DATABASE': PR_ID.replaceAll('-', '_'),
                                    'DB_USERNAME': MDE_DATABASE_USERNAME,
                                    'DB_HOST': MDE_DATABASE_HOST,
                                    'APP_URL': APP_URL             
                                ]
                                
                                def templateContent = readFile('./env.tpl')
                                
                                vars.each { key, value ->
                                    def placeholder = '\\$\\{' + key + '\\}'
                                    def escapedValue = value.toString().replaceAll('\\\\', '\\\\\\\\').replaceAll('\\$', '\\\\\\$')
                                    templateContent = templateContent.replaceAll(placeholder, escapedValue)
                                }
                                
                                writeFile file: '.env.mde', text: templateContent

                                sh '''
                                    cat .env.mde .env.base | awk -F= '!seen[$1]++' > ${WORKSPACE}/${HELM_REPO}/files/vars/.env
                                    rm .env.base .env.mde
                                '''
                            }
                        } else {
                            sh '''
                                mv ${HELM_REPO}/files/.env.base ${HELM_REPO}/files/vars/.env
                            '''
                        }

                        // Debug helper: expose env file contents to locate malformed secrets
                        sh '''
                            echo '--- DEBUG: Dumping ${HELM_REPO}/files/vars/.env with line numbers ---'
                            nl -ba ${HELM_REPO}/files/vars/.env
                            echo '--- DEBUG: Lines without an assignment (potential bad Helm keys) ---'
                            awk 'length($0) > 0 && index($0, "=") == 0 {printf("INVALID %05d %s\n", NR, $0)}' ${HELM_REPO}/files/vars/.env || true
                        '''
                    }
                }
            }
        }

        stage('Deploy Helm Chart') {
            steps {
                lock("deploy-${params.ENV}") {
                    script {
                        sh """
                            DEPLOY_TS=$(date +%s)
                            helm template api-core ./${HELM_REPO} \
                                --namespace ${env.NAMESPACE} \
                                --set-string image.api=${ECR_API_IMAGE} \
                                --set-string image.queue=${ECR_QUE_IMAGE} \
                                --set-string deploy.date=\${DEPLOY_TS} \
                                --set-string gitBranchName=${BRANCH_NAME} \
                                --set-file envFile=${HELM_REPO}/files/vars/.env \
                                --set-string supervisorConfig=files/vars/supervisor.conf \
                                -f ${HELM_REPO}/values.yaml \
                                > helm-debug-output.yaml
                            printf '%s' "\${DEPLOY_TS}" > helm-debug-timestamp.txt
                        """

                        env.DEPLOY_TIMESTAMP = readFile('helm-debug-timestamp.txt').trim()

                        sh '''
                            echo "--- DEBUG: helm template deploy.timestamp: ${DEPLOY_TIMESTAMP} ---"
                            echo '--- DEBUG: Rendered api-core-env ConfigMap from helm template ---'
                            awk '
                                function flush() {
                                    if (doc == "ConfigMap" && index(buf, "name: api-core-env")) {
                                        printf "%s", buf
                                        found = 1
                                    }
                                    buf = ""; doc = ""
                                }
                                /^---$/ { flush(); if (found) exit; next }
                                { if ($0 ~ /^kind: /) doc = $2 }
                                { if (doc == "ConfigMap") buf = buf sprintf("%05d %s\n", NR, $0) }
                                END { flush() }
                            ' helm-debug-output.yaml || true
                            echo '--- DEBUG: End of ConfigMap dump ---'
                        '''

                        sh 'rm -f helm-debug-output.yaml helm-debug-timestamp.txt'
                    }

                    sh "helm upgrade --install api-core ./${HELM_REPO} --install --create-namespace --namespace ${env.NAMESPACE} --kube-context ${EKS_CLUSTER_NAME} --set-string image.api=${ECR_API_IMAGE} --set-string image.queue=${ECR_QUE_IMAGE} --set-string deploy.date=`date +%s` --set-string gitBranchName=${BRANCH_NAME} --set-file envFile=${HELM_REPO}/files/vars/.env --set-string supervisorConfig=files/vars/supervisor.conf -f ${HELM_REPO}/values.yaml"
                    sh "kubectl rollout status deployment/api-core --namespace ${env.NAMESPACE} --context ${EKS_CLUSTER_NAME}"
                }
            }
        }
    }
    post {
        success {
            script {
                if (params.ENV == 'mde') {
                    notifyMDE()
                }
            }
        }
        always {
            script {
                // Revert permission changes to allow proper cleanup
                try {
                    dir("${API_CORE_REPO}") {
                        sh """
                            # Reset ownership back to the current user (Jenkins)
                            sudo chown -R ${BASE_RUNNER_USER}:${BASE_RUNNER_USER} . || true
                            
                            # Reset permissions to allow deletion
                            find . -type f -exec sudo chmod 644 {} + 2>/dev/null || true
                            find . -type d -exec sudo chmod 755 {} + 2>/dev/null || true
                        """
                    }
                } catch (Exception e) {
                    echo "Warning: Could not reset permissions: ${e.getMessage()}"
                }
            }
            cleanWs()
        }
    }
}

def getGitHubAppToken() {
    withCredentials([file(credentialsId: 'github-app-private-key', variable: 'GH_APP_PEM_FILE')]) {
        def rawToken = sh(script: '''
            now=$(date +%s)
            exp=$((now + 600))
            
            header='{"alg":"RS256","typ":"JWT"}'
            payload='{"iat":'${now}',"exp":'${exp}',"iss":"'${GH_APP_ID}'"}'
            
            base64_header=$(echo -n "${header}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
            base64_payload=$(echo -n "${payload}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
            
            signature=$(echo -n "${base64_header}.${base64_payload}" | openssl dgst -sha256 -sign "${GH_APP_PEM_FILE}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
            
            jwt="${base64_header}.${base64_payload}.${signature}"
            
            curl -s -X POST \
                -H "Authorization: Bearer ${jwt}" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/app/installations/${GH_INSTALLATION_ID}/access_tokens" | jq -r .token
        ''', returnStdout: true).trim()
        
        return rawToken
    }
}

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

def notifyMDE() {
    sh """
        curl -s -X POST \\
            -H 'Authorization: Bearer ${TOKEN}' \\
            -H 'Accept: application/vnd.github.v3+json' \\
            -d '{"body": "Hi, your environment is ready to use at: ${APP_URL}"}' \\
            'https://api.github.com/repos/${GITHUB_ORG}/${API_CORE_REPO}/issues/${PR_NUMBER}/comments' > /dev/null
    """
}
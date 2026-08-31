//==============================================================================
// REPOSITORY-CONFIGURED INGRESS PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    def runtimeConfiguration = [:]

    pipeline {
        agent any

        options {
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 30, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        stages {
            stage('Checkout Configuration') {
                steps {
                    checkout scm
                }
            }

            stage('Prepare') {
                steps {
                    script {
                        def outputFile = "${pwd(tmp: true)}/ingress-pipeline-outputs"
                        withEnv(["GITHUB_OUTPUT=${outputFile}"]) {
                            sh '''
                                set -eu
                                : > "$GITHUB_OUTPUT"
                                bash scripts/validate-config.sh
                                bash scripts/prepare-ingress-inputs.sh
                            '''
                        }

                        def preparedOutputs = [:]
                        readFile(file: outputFile).readLines().findAll { it }.each { line ->
                            def delimiter = line.indexOf('=')
                            if (delimiter <= 0) {
                                error('Invalid prepared ingress output')
                            }
                            preparedOutputs[line.substring(0, delimiter)] = line.substring(delimiter + 1)
                        }
                        sh "rm -f -- '${outputFile}'"

                        [
                            'automation_ref',
                            'automation_repository',
                            'compartment_ocid',
                            'connector_targets',
                            'region',
                            'tunnel_secret_name',
                            'verification_url'
                        ].each { requiredOutput ->
                            if (!preparedOutputs[requiredOutput]) {
                                error("Missing prepared ingress output: ${requiredOutput}")
                            }
                        }

                        runtimeConfiguration.putAll(preparedOutputs)
                    }
                }
            }

            stage('Checkout Automation') {
                steps {
                    script {
                        dir('.host-automation') {
                            deleteDir()
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "refs/tags/${runtimeConfiguration.automation_ref}"]],
                                userRemoteConfigs: [[
                                    url: "https://github.com/${runtimeConfiguration.automation_repository}.git"
                                ]]
                            ])
                        }
                    }
                }
            }

            stage('Approve') {
                steps {
                    input message: 'Deploy the production Cloudflare connector?', ok: 'Deploy'
                }
            }

            stage('Deploy') {
                steps {
                    script {
                        ociRunCommand(
                            action: 'deploy',
                            authenticationMode: 'instance-principal',
                            compartmentOcid: runtimeConfiguration.compartment_ocid,
                            region: runtimeConfiguration.region,
                            displayName: 'production-ingress-connector',
                            prependAction: false,
                            requiredOutputMarker: 'cloudflare_tunnel=ready',
                            scriptPath: "${pwd()}/.host-automation/scripts/linux/cloudflare/bootstrap-cloudflared.sh",
                            targetsJson: runtimeConfiguration.connector_targets,
                            timeoutSeconds: configuration.timeoutSeconds ?: 300,
                            vaultSecretName: runtimeConfiguration.tunnel_secret_name
                        )
                    }
                }
            }

            stage('Verify Public Route') {
                steps {
                    sh "bash scripts/verify-public-ingress.sh '${runtimeConfiguration.verification_url}'"
                }
            }
        }
    }
}
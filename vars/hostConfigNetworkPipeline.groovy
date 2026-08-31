//==============================================================================
// REPOSITORY-CONFIGURED HOST NETWORK PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    def runtimeConfiguration = [:]

    pipeline {
        agent { label 'platform' }

        options {
            ansiColor('xterm')
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 30, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        parameters {
            choice(
                name: 'OPERATION',
                choices: ['preflight', 'configure', 'verify'],
                description: 'Secondary private IP lifecycle operation'
            )
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
                        def outputFile = "${pwd(tmp: true)}/network-pipeline-outputs"
                        withEnv(["GITHUB_OUTPUT=${outputFile}"]) {
                            sh '''
                                set -eu
                                : > "$GITHUB_OUTPUT"
                                bash scripts/validate-config.sh
                                bash scripts/prepare-network-inputs.sh "$OPERATION"
                            '''
                        }

                        def preparedOutputs = [:]
                        readFile(file: outputFile).readLines().findAll { it }.each { line ->
                            def delimiter = line.indexOf('=')
                            if (delimiter <= 0) {
                                error('Invalid prepared network output')
                            }
                            preparedOutputs[line.substring(0, delimiter)] = line.substring(delimiter + 1)
                        }
                        sh "rm -f -- '${outputFile}'"

                        [
                            'automation_ref',
                            'automation_repository',
                            'compartment_ocid',
                            'region',
                            'required_output_marker',
                            'script_path',
                            'targets_json'
                        ].each { requiredOutput ->
                            if (!preparedOutputs[requiredOutput]) {
                                error("Missing prepared network output: ${requiredOutput}")
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
                when {
                    expression { params.OPERATION == 'configure' }
                }
                steps {
                    input message: 'Configure production secondary private IPs?', ok: 'Configure'
                }
            }

            stage('Execute') {
                steps {
                    script {
                        ociRunCommand(
                            action: params.OPERATION == 'configure' ? 'deploy' : 'verify',
                            authenticationMode: 'instance-principal',
                            compartmentOcid: runtimeConfiguration.compartment_ocid,
                            region: runtimeConfiguration.region,
                            displayName: "production-host-network-${params.OPERATION}",
                            prependAction: false,
                            requiredOutputMarker: runtimeConfiguration.required_output_marker,
                            scriptPath: "${pwd()}/.host-automation/${runtimeConfiguration.script_path}",
                            targetsJson: runtimeConfiguration.targets_json,
                            timeoutSeconds: configuration.timeoutSeconds ?: 300
                        )
                    }
                }
            }
        }
    }
}
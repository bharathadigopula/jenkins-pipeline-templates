//==============================================================================
// KUBERNETES APPLICATION DECLARATIVE PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    def runtimeConfiguration = [:]

    pipeline {
        agent { label 'platform' }

        options {
            ansiColor('xterm')
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 60, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        parameters {
            choice(name: 'ACTION', choices: ['status', 'deploy', 'backup', 'restore'], description: 'Production lifecycle action')
            string(name: 'IMAGE_TAG', defaultValue: '', description: 'Published application image tag for deployment')
            string(name: 'IMAGE_DIGEST', defaultValue: '', description: 'Published application image SHA-256 digest for deployment')
            string(name: 'RESTORE_SNAPSHOT', defaultValue: 'latest', description: 'Restic snapshot ID used only for restore')
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
                        def outputFile = "${pwd(tmp: true)}/wordpress-pipeline-outputs"
                        withEnv([
                            "GITHUB_OUTPUT=${outputFile}",
                            "WORDPRESS_ACTION=${params.ACTION}",
                            "WORDPRESS_BUILD_NUMBER=${env.BUILD_NUMBER}",
                            "WORDPRESS_IMAGE_DIGEST=${params.IMAGE_DIGEST}",
                            "WORDPRESS_IMAGE_TAG=${params.IMAGE_TAG}",
                            "WORDPRESS_RESTORE_SNAPSHOT=${params.RESTORE_SNAPSHOT}"
                        ]) {
                            sh "bash '${configuration.prepareScript ?: 'scripts/prepare-wordpress-inputs.sh'}'"
                        }

                        readFile(file: outputFile).readLines().findAll { it }.each { line ->
                            def delimiter = line.indexOf('=')
                            if (delimiter <= 0) {
                                error('Invalid prepared WordPress output')
                            }
                            runtimeConfiguration[line.substring(0, delimiter)] = line.substring(delimiter + 1)
                        }
                        sh "rm -f -- '${outputFile}'"

                        ['automation_ref', 'automation_repository', 'compartment_ocid', 'operation_targets',
                         'region', 'required_output_marker', 'validation_targets'].each { requiredOutput ->
                            if (!runtimeConfiguration[requiredOutput]) {
                                error("Missing prepared WordPress output: ${requiredOutput}")
                            }
                        }
                    }
                }
            }

            stage('Checkout Automation') {
                steps {
                    script {
                        dir('.wordpress-automation') {
                            deleteDir()
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "refs/tags/${runtimeConfiguration.automation_ref}"]],
                                userRemoteConfigs: [[url: "https://github.com/${runtimeConfiguration.automation_repository}.git"]]
                            ])
                        }
                    }
                }
            }

            stage('Validate') {
                steps {
                    sh 'bash .wordpress-automation/scripts/validate.sh'
                    script {
                        ociRunCommand(
                            action: 'validate',
                            authenticationMode: 'instance-principal',
                            compartmentOcid: runtimeConfiguration.compartment_ocid,
                            region: runtimeConfiguration.region,
                            displayName: 'wordpress-preflight',
                            prependAction: false,
                            requiredOutputMarker: 'wordpress_validation=ready',
                            scriptPath: "${pwd()}/.wordpress-automation/scripts/bootstrap.sh",
                            targetsJson: runtimeConfiguration.validation_targets,
                            timeoutSeconds: configuration.timeoutSeconds ?: 900
                        )
                    }
                }
            }

            stage('Approve') {
                when {
                    expression { params.ACTION != 'status' }
                }
                steps {
                    input message: "Run WordPress ${params.ACTION} in production?", ok: 'Run'
                }
            }

            stage('Operate') {
                steps {
                    script {
                        ociRunCommand(
                            action: params.ACTION,
                            authenticationMode: 'instance-principal',
                            compartmentOcid: runtimeConfiguration.compartment_ocid,
                            region: runtimeConfiguration.region,
                            displayName: "wordpress-${params.ACTION}",
                            prependAction: false,
                            requiredOutputMarker: runtimeConfiguration.required_output_marker,
                            scriptPath: "${pwd()}/.wordpress-automation/scripts/bootstrap.sh",
                            targetsJson: runtimeConfiguration.operation_targets,
                            timeoutSeconds: configuration.timeoutSeconds ?: 3600,
                            vaultSecretName: runtimeConfiguration.vault_secret_name,
                            additionalVaultSecretName: runtimeConfiguration.additional_vault_secret_name,
                            tertiaryVaultSecretName: runtimeConfiguration.tertiary_vault_secret_name
                        )
                    }
                }
            }

            stage('Verify Public Route') {
                when {
                    expression { params.ACTION == 'deploy' }
                }
                steps {
                    script {
                        withEnv(["WORDPRESS_VERIFICATION_URL=${runtimeConfiguration.verification_url}"]) {
                            sh 'curl --fail --silent --show-error --location --retry 6 --retry-delay 10 "$WORDPRESS_VERIFICATION_URL/wp-login.php" >/dev/null'
                        }
                    }
                }
            }
        }

        post {
            cleanup {
                deleteDir()
            }
        }
    }
}
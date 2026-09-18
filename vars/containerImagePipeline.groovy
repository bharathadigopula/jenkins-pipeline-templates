//==============================================================================
// SECURE CONTAINER IMAGE DECLARATIVE PIPELINE
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
            choice(name: 'ACTION', choices: ['validate', 'publish'], description: 'Validate only or publish and deploy')
        }

        environment {
            CONTAINER_IMAGE_PLATFORMS = "${configuration.platforms ?: 'linux/amd64,linux/arm64'}"
            CONTAINER_IMAGE_REPOSITORY = "${configuration.imageRepository ?: ''}"
            CONTAINER_OUTPUT_DIRECTORY = 'build'
            TRIVY_IMAGE = "${configuration.trivyImage ?: 'aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969'}"
        }

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                    script {
                        runtimeConfiguration.imageTag = "sha-${env.GIT_COMMIT.take(12)}"
                        env.CONTAINER_IMAGE_TAG = runtimeConfiguration.imageTag
                    }
                }
            }

            stage('Validate') {
                steps {
                    sh "bash '${configuration.validationScript ?: 'scripts/validate.sh'}'"
                    libraryScript('container-image.sh', 'validate')
                }
            }

            stage('Build') {
                steps {
                    libraryScript('container-image.sh', 'build')
                }
            }

            stage('Scan And SBOM') {
                steps {
                    libraryScript('container-image.sh', 'scan')
                    archiveArtifacts artifacts: 'build/sbom.cdx.json', fingerprint: true
                }
            }

            stage('Approve Publication') {
                when {
                    expression { params.ACTION == 'publish' }
                }
                steps {
                    input message: "Publish ${configuration.imageRepository}:${runtimeConfiguration.imageTag}?", ok: 'Publish'
                }
            }

            stage('Publish') {
                when {
                    expression { params.ACTION == 'publish' }
                }
                steps {
                    withCredentials([usernamePassword(
                        credentialsId: configuration.registryCredentialId ?: 'github-scm',
                        usernameVariable: 'REGISTRY_USERNAME',
                        passwordVariable: 'REGISTRY_PASSWORD'
                    )]) {
                        sh 'printf %s "$REGISTRY_PASSWORD" | docker login ghcr.io --username "$REGISTRY_USERNAME" --password-stdin'
                        libraryScript('container-image.sh', 'publish')
                        sh 'docker logout ghcr.io >/dev/null'
                    }
                    archiveArtifacts artifacts: 'build/image-digest,build/image-metadata.json', fingerprint: true
                }
            }

            stage('Deploy') {
                when {
                    expression { params.ACTION == 'publish' && configuration.deploymentJob }
                }
                steps {
                    script {
                        def imageDigest = readFile('build/image-digest').trim()
                        build job: configuration.deploymentJob, wait: false, parameters: [
                            string(name: 'ACTION', value: 'deploy'),
                            string(name: 'IMAGE_DIGEST', value: imageDigest),
                            string(name: 'IMAGE_TAG', value: runtimeConfiguration.imageTag)
                        ]
                    }
                }
            }
        }

        post {
            cleanup {
                sh 'docker logout ghcr.io >/dev/null 2>&1 || true'
                deleteDir()
            }
        }
    }
}
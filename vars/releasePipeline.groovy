//==============================================================================
// RELEASE DECLARATIVE PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    pipeline {
        //======================================================================
        // PIPELINE AGENT
        //======================================================================

        agent { label 'platform' }

        //======================================================================
        // PIPELINE CONTROLS
        //======================================================================

        options {
            ansiColor('xterm')
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 15, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        //======================================================================
        // RELEASE ENVIRONMENT
        //======================================================================

        environment {
            RELEASE_ACTION = "${configuration.action ?: 'validate'}"
            RELEASE_TAG = "${configuration.tag ?: ''}"
        }

        //======================================================================
        // RELEASE STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Validate') {
                steps {
                    libraryScript('release.sh', 'validate')
                }
            }

            stage('Approve') {
                when {
                    expression { env.RELEASE_ACTION == 'create' }
                }
                steps {
                    input message: "Create immutable release ${env.RELEASE_TAG}?", ok: 'Create release'
                }
            }

            stage('Create') {
                when {
                    expression { env.RELEASE_ACTION == 'create' }
                }
                steps {
                    withCredentials([string(credentialsId: configuration.githubCredentialId ?: 'github-token', variable: 'GITHUB_TOKEN')]) {
                        libraryScript('release.sh', 'create')
                    }
                }
            }
        }
    }
}
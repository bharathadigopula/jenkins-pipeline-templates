//==============================================================================
// DOCKER COMPOSE DECLARATIVE PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    pipeline {
        //======================================================================
        // PIPELINE AGENT
        //======================================================================

        agent any

        //======================================================================
        // PIPELINE CONTROLS
        //======================================================================

        options {
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 30, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        //======================================================================
        // COMPOSE ENVIRONMENT
        //======================================================================

        environment {
            COMPOSE_ACTION = "${configuration.action ?: 'validate'}"
            COMPOSE_FILE = "${configuration.composeFile ?: 'compose.yaml'}"
            DEPLOY_SCRIPT = "${configuration.deployScript ?: ''}"
        }

        //======================================================================
        // COMPOSE STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Validate') {
                steps {
                    libraryScript('compose.sh', 'validate')
                }
            }

            stage('Dry Run') {
                when {
                    expression { env.COMPOSE_ACTION in ['dry-run', 'deploy'] }
                }
                steps {
                    libraryScript('compose.sh', 'dry-run')
                }
            }

            stage('Approve') {
                when {
                    expression { env.COMPOSE_ACTION == 'deploy' }
                }
                steps {
                    input message: 'Deploy the validated Compose release?', ok: 'Deploy'
                }
            }

            stage('Deploy') {
                when {
                    expression { env.COMPOSE_ACTION == 'deploy' }
                }
                steps {
                    libraryScript('compose.sh', 'deploy')
                }
            }
        }
    }
}
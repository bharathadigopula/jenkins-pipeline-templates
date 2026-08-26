//==============================================================================
// HOST DEPLOYMENT DECLARATIVE PIPELINE
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
            timeout(time: configuration.timeoutMinutes ?: 40, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        //======================================================================
        // DEPLOYMENT STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Validate') {
                steps {
                    ociRunCommand(configuration + [action: 'validate'])
                }
            }

            stage('Dry Run') {
                when {
                    expression { (configuration.action ?: 'validate') in ['dry-run', 'deploy'] }
                }
                steps {
                    ociRunCommand(configuration + [action: 'dry-run'])
                }
            }

            stage('Approve') {
                when {
                    expression { (configuration.action ?: 'validate') == 'deploy' }
                }
                steps {
                    input message: "Deploy ${configuration.displayName ?: 'host automation'}?", ok: 'Deploy'
                }
            }

            stage('Deploy') {
                when {
                    expression { (configuration.action ?: 'validate') == 'deploy' }
                }
                steps {
                    ociRunCommand(configuration + [action: 'deploy'])
                }
            }
        }
    }
}
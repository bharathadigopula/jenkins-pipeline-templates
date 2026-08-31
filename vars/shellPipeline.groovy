//==============================================================================
// SHELL VALIDATION DECLARATIVE PIPELINE
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
            timeout(time: configuration.timeoutMinutes ?: 10, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        //======================================================================
        // SHELL ENVIRONMENT
        //======================================================================

        environment {
            SHELL_SEARCH_PATH = "${configuration.searchPath ?: '.'}"
            VALIDATION_SCRIPT = "${configuration.validationScript ?: ''}"
        }

        //======================================================================
        // SHELL VALIDATION STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('ShellCheck') {
                steps {
                    libraryScript('shell-validate.sh')
                }
            }

            stage('Repository Validation') {
                when {
                    expression { env.VALIDATION_SCRIPT?.trim() }
                }
                steps {
                    sh 'bash "$VALIDATION_SCRIPT"'
                }
            }
        }
    }
}
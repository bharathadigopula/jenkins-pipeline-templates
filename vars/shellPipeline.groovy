//==============================================================================
// SHELL VALIDATION DECLARATIVE PIPELINE
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
            timeout(time: configuration.timeoutMinutes ?: 10, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        //======================================================================
        // SHELL ENVIRONMENT
        //======================================================================

        environment {
            SHELL_SEARCH_PATH = "${configuration.searchPath ?: '.'}"
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
        }
    }
}
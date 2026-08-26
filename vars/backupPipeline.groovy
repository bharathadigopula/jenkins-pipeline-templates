//==============================================================================
// BACKUP DECLARATIVE PIPELINE
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
        // BACKUP STAGES
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

            stage('Approve') {
                steps {
                    input message: "Run ${configuration.displayName ?: 'host'} backup?", ok: 'Run backup'
                }
            }

            stage('Backup') {
                steps {
                    ociRunCommand(configuration + [action: 'backup'])
                }
            }
        }
    }
}
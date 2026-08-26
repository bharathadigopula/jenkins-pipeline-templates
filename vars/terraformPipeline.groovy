//==============================================================================
// TERRAFORM DECLARATIVE PIPELINE
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
        // TERRAFORM ENVIRONMENT
        //======================================================================

        environment {
            TERRAFORM_DIRECTORY = "${configuration.directory ?: '.'}"
            TERRAFORM_ACTION = "${configuration.action ?: 'validate'}"
            TERRAFORM_PLAN_FILE = "${configuration.planFile ?: 'tfplan'}"
        }

        //======================================================================
        // TERRAFORM STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Validate') {
                steps {
                    libraryScript('terraform.sh', 'validate')
                }
            }

            stage('Plan') {
                when {
                    expression { env.TERRAFORM_ACTION in ['plan', 'apply'] }
                }
                steps {
                    libraryScript('terraform.sh', 'plan')
                    archiveArtifacts artifacts: "${env.TERRAFORM_DIRECTORY}/${env.TERRAFORM_PLAN_FILE}*", fingerprint: true
                }
            }

            stage('Approve') {
                when {
                    expression { env.TERRAFORM_ACTION == 'apply' }
                }
                steps {
                    script {
                        env.TERRAFORM_APPROVED_PLAN_SHA256 = input(
                            message: 'Approve the reviewed saved Terraform plan',
                            ok: 'Apply exact plan',
                            parameters: [string(name: 'PLAN_SHA256', description: 'SHA256 emitted by the plan stage')]
                        )
                    }
                }
            }

            stage('Apply') {
                when {
                    expression { env.TERRAFORM_ACTION == 'apply' }
                }
                steps {
                    libraryScript('terraform.sh', 'apply')
                }
            }
        }
    }
}
//==============================================================================
// REPOSITORY VALIDATION DECLARATIVE PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    def terraformDirectories = configuration.terraformDirectories ?: []
    def validationCommands = configuration.validationCommands ?: []

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
            timeout(time: configuration.timeoutMinutes ?: 20, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        //======================================================================
        // VALIDATION ENVIRONMENT
        //======================================================================

        environment {
            GROOVY_SEARCH_PATH = "${configuration.groovySearchPath ?: ''}"
            SHELL_SEARCH_PATH = "${configuration.shellSearchPath ?: ''}"
            VALIDATION_SCRIPT = "${configuration.validationScript ?: ''}"
        }

        //======================================================================
        // VALIDATION STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Commit Status') {
                when {
                    expression { configuration.githubRepository }
                }
                steps {
                    githubStatus(
                        repository: configuration.githubRepository,
                        state: 'pending',
                        description: 'Jenkins validation is running'
                    )
                }
            }

            stage('ShellCheck') {
                when {
                    expression { env.SHELL_SEARCH_PATH?.trim() }
                }
                steps {
                    libraryScript('shell-validate.sh')
                }
            }

            stage('GitHub Workflows') {
                when {
                    expression { configuration.validateWorkflows ?: false }
                }
                steps {
                    libraryScript('actionlint.sh')
                }
            }

            stage('Groovy') {
                when {
                    expression { env.GROOVY_SEARCH_PATH?.trim() }
                }
                steps {
                    libraryScript('groovy-validate.sh')
                }
            }

            stage('Terraform') {
                when {
                    expression { !terraformDirectories.isEmpty() }
                }
                steps {
                    script {
                        terraformDirectories.each { terraformDirectory ->
                            withEnv(["TERRAFORM_DIRECTORY=${terraformDirectory}"]) {
                                libraryScript('terraform.sh', 'validate')
                            }
                        }
                    }
                }
            }

            stage('Repository Tests') {
                when {
                    expression { env.VALIDATION_SCRIPT?.trim() }
                }
                steps {
                    sh 'bash "$VALIDATION_SCRIPT"'
                }
            }

            stage('Additional Validation') {
                when {
                    expression { !validationCommands.isEmpty() }
                }
                steps {
                    script {
                        validationCommands.each { validationCommand ->
                            sh validationCommand
                        }
                    }
                }
            }
        }

        post {
            success {
                script {
                    if (configuration.githubRepository) {
                        githubStatus(
                            repository: configuration.githubRepository,
                            state: 'success',
                            description: 'Jenkins validation passed'
                        )
                    }
                }
            }
            unsuccessful {
                script {
                    if (configuration.githubRepository) {
                        githubStatus(
                            repository: configuration.githubRepository,
                            state: 'failure',
                            description: 'Jenkins validation failed'
                        )
                    }
                }
            }
        }
    }
}
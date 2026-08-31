//==============================================================================
// JENKINS PIPELINE TEMPLATE VALIDATION
//==============================================================================

@Library('jenkins-pipeline-templates@v1.2.0') _

repositoryValidationPipeline(
    groovySearchPath: 'vars',
    shellSearchPath: '.',
    validationScript: 'resources/scripts/validate-library.sh',
    validateWorkflows: true
)
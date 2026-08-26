//==============================================================================
// GITHUB COMMIT STATUS STEP
//==============================================================================

def call(Map configuration = [:]) {
    //==========================================================================
    // REQUIRED CONFIGURATION
    //==========================================================================

    if (!configuration.repository) {
        error('repository is required')
    }

    //==========================================================================
    // GITHUB CREDENTIAL BINDING
    //==========================================================================

    withCredentials([string(credentialsId: configuration.credentialId ?: 'github-token', variable: 'GITHUB_TOKEN')]) {
        //======================================================================
        // STATUS ENVIRONMENT
        //======================================================================

        withEnv([
            "GITHUB_REPOSITORY=${configuration.repository}",
            "GITHUB_STATUS_STATE=${configuration.state ?: 'pending'}",
            "GITHUB_STATUS_DESCRIPTION=${configuration.description ?: 'Jenkins pipeline status'}",
            "GITHUB_STATUS_CONTEXT=${configuration.context ?: 'continuous-integration/jenkins'}"
        ]) {
            libraryScript('github-status.sh')
        }
    }
}
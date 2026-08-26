//==============================================================================
// OCI RUN COMMAND STEP
//==============================================================================

def call(Map configuration = [:]) {
    //==========================================================================
    // REQUIRED CONFIGURATION
    //==========================================================================

    if (!configuration.credentialId) {
        error('credentialId is required')
    }

    //==========================================================================
    // OCI CREDENTIAL BINDING
    //==========================================================================

    withCredentials([file(credentialsId: configuration.credentialId, variable: 'OCI_CREDENTIALS_FILE')]) {
        //======================================================================
        // RUN COMMAND ENVIRONMENT
        //======================================================================

        withEnv([
            "OCI_RUN_COMMAND_ACTION=${configuration.action ?: 'validate'}",
            "RUN_COMMAND_SCRIPT_PATH=${configuration.scriptPath ?: ''}",
            "RUN_COMMAND_TARGETS=${configuration.targetsJson ?: '[]'}",
            "RUN_COMMAND_DISPLAY_NAME=${configuration.displayName ?: 'jenkins-run-command'}",
            "RUN_COMMAND_REQUIRED_OUTPUT_MARKER=${configuration.requiredOutputMarker ?: ''}",
            "RUN_COMMAND_TIMEOUT_SECONDS=${configuration.timeoutSeconds ?: 300}",
            "RUN_COMMAND_VAULT_SECRET_NAME=${configuration.vaultSecretName ?: ''}"
        ]) {
            libraryScript('oci-run-command.sh')
        }
    }
}
//==============================================================================
// OCI RUN COMMAND STEP
//==============================================================================

def call(Map configuration = [:]) {
    //==========================================================================
    // AUTHENTICATION CONFIGURATION
    //==========================================================================

    def authenticationMode = configuration.authenticationMode ?: 'api-key'
    if (!(authenticationMode in ['api-key', 'instance-principal'])) {
        error('authenticationMode must be api-key or instance-principal')
    }

    if (authenticationMode == 'api-key' && !configuration.credentialId) {
        error('credentialId is required for api-key authentication')
    }

    if (authenticationMode == 'instance-principal' &&
        (!configuration.compartmentOcid || !configuration.region)) {
        error('compartmentOcid and region are required for instance-principal authentication')
    }

    //==========================================================================
    // RUN COMMAND EXECUTION
    //==========================================================================

    def executeRunCommand = {
        withEnv([
            "OCI_RUN_COMMAND_AUTH_MODE=${authenticationMode}",
            "OCI_RUN_COMMAND_ACTION=${configuration.action ?: 'validate'}",
            "OCI_RUN_COMMAND_COMPARTMENT_OCID=${configuration.compartmentOcid ?: ''}",
            "OCI_RUN_COMMAND_REGION=${configuration.region ?: ''}",
            "RUN_COMMAND_SCRIPT_PATH=${configuration.scriptPath ?: ''}",
            "RUN_COMMAND_TARGETS=${configuration.targetsJson ?: '[]'}",
            "RUN_COMMAND_DISPLAY_NAME=${configuration.displayName ?: 'jenkins-run-command'}",
            "RUN_COMMAND_DETACHED=${configuration.detached ?: false}",
            "RUN_COMMAND_REQUIRED_OUTPUT_MARKER=${configuration.requiredOutputMarker ?: ''}",
            "RUN_COMMAND_TIMEOUT_SECONDS=${configuration.timeoutSeconds ?: 300}",
            "RUN_COMMAND_VAULT_SECRET_NAME=${configuration.vaultSecretName ?: ''}",
            "RUN_COMMAND_ADDITIONAL_VAULT_SECRET_NAME=${configuration.additionalVaultSecretName ?: ''}",
            "RUN_COMMAND_TERTIARY_VAULT_SECRET_NAME=${configuration.tertiaryVaultSecretName ?: ''}"
        ]) {
            libraryScript('oci-run-command.sh')
        }
    }

    if (authenticationMode == 'instance-principal') {
        executeRunCommand()
        return
    }

    //==========================================================================
    // OCI API KEY CREDENTIAL BINDING
    //==========================================================================

    withCredentials([file(credentialsId: configuration.credentialId, variable: 'OCI_CREDENTIALS_FILE')]) {
        executeRunCommand()
    }
}
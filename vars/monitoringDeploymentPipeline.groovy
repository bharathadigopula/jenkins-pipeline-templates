//==============================================================================
// MONITORING DEPLOYMENT PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    //==========================================================================
    // MONITORING DEPLOYMENT DEFAULTS
    //==========================================================================

    def deploymentConfiguration = [
        displayName: 'monitoring-stack',
        requiredOutputMarker: 'monitoring_',
        timeoutSeconds: 900
    ] + configuration

    //==========================================================================
    // HOST DEPLOYMENT DELEGATION
    //==========================================================================

    hostDeploymentPipeline(deploymentConfiguration)
}
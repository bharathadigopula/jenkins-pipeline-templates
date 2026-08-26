//==============================================================================
// JENKINS DEPLOYMENT PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    //==========================================================================
    // JENKINS DEPLOYMENT DEFAULTS
    //==========================================================================

    def deploymentConfiguration = [
        displayName: 'jenkins-controller',
        requiredOutputMarker: 'jenkins_',
        timeoutSeconds: 1200
    ] + configuration

    //==========================================================================
    // HOST DEPLOYMENT DELEGATION
    //==========================================================================

    hostDeploymentPipeline(deploymentConfiguration)
}
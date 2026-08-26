//==============================================================================
// VERSIONED LIBRARY SCRIPT EXECUTION
//==============================================================================

def call(String resourceName, String action = '') {
    //==========================================================================
    // RESOURCE MATERIALISATION
    //==========================================================================

    def resourceContent = libraryResource("scripts/${resourceName}")
    def toolContainerContent = libraryResource('scripts/tool-container.sh')
    def resourceDirectory = '.jenkins-library/scripts'
    def temporaryScript = "${resourceDirectory}/${resourceName}"
    sh "mkdir -p '${resourceDirectory}'"
    writeFile file: temporaryScript, text: resourceContent
    writeFile file: "${resourceDirectory}/tool-container.sh", text: toolContainerContent
    sh "chmod 0700 '${temporaryScript}' '${resourceDirectory}/tool-container.sh'"

    //==========================================================================
    // RESOURCE EXECUTION
    //==========================================================================

    def command = action ? "bash '${temporaryScript}' '${action}'" : "bash '${temporaryScript}'"
    sh command
}
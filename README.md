<!--
==============================================================================
JENKINS PIPELINE TEMPLATES
==============================================================================
-->

# Jenkins Pipeline Templates

A versioned Jenkins Shared Library for Terraform, Bash, Docker Compose, OCI Run Command, release, backup, and deployment pipelines. Declarative Groovy files orchestrate Jenkins stages while operational behavior remains in ShellCheck-validated Bash resources.

<!--
==============================================================================
LIBRARY REQUIREMENTS
==============================================================================
-->

## Requirements

- Jenkins LTS with Pipeline, Credentials Binding, Git, and SSH Agent plugins
- Docker CLI connected to a Docker daemon
- `bash`, `curl`, `git`, `jq`, and `sha256sum` in the controller or agent image
- A named Docker volume containing `JENKINS_HOME`
- A GitHub secret-text credential for status and release operations
- An OCI secret-file credential for OCI Run Command

The tool runner uses `--volumes-from` with the Jenkins container ID so pinned Terraform, ShellCheck, and Python tool containers can access the same workspace without host-path assumptions.

<!--
==============================================================================
SHARED LIBRARY CONFIGURATION
==============================================================================
-->

## Jenkins Configuration

Configure a Global Pipeline Library with:

| Setting | Value |
| --- | --- |
| Name | `jenkins-pipeline-templates` |
| Default version | An immutable release such as `v1.0.0` |
| Retrieval | Modern SCM |
| Source | This repository's Git URL |
| Credentials | GitHub credential when required |

Consumers should pin the library in each Jenkinsfile with `@Library('jenkins-pipeline-templates@v1.0.0') _`.

<!--
==============================================================================
PUBLIC PIPELINE STEPS
==============================================================================
-->

## Pipeline Steps

| Step | Purpose |
| --- | --- |
| `terraformPipeline` | Format, initialize, validate, plan, approve, and apply an exact saved plan |
| `shellPipeline` | Discover and validate Bash scripts with pinned ShellCheck |
| `composePipeline` | Validate, dry-run, approve, and invoke a deployment script |
| `ociRunCommand` | Execute a versioned host script through OCI Run Command |
| `hostDeploymentPipeline` | Validate, dry-run, approve, and deploy host automation |
| `monitoringDeploymentPipeline` | Low-resource monitoring deployment defaults |
| `jenkinsDeploymentPipeline` | Jenkins controller deployment defaults |
| `releasePipeline` | Validate and create an immutable GitHub release |
| `backupPipeline` | Validate and execute an approved remote backup |
| `githubStatus` | Report Jenkins state to a GitHub commit status context |

<!--
==============================================================================
TERRAFORM SAFETY CONTRACT
==============================================================================
-->

## Terraform Safety

`terraformPipeline` applies only the binary plan produced by the plan stage. It records the plan SHA256, archives the plan and checksum, and requires an operator to enter that exact checksum at approval. Apply is rejected if the current, recorded, and approved checksums do not all match.

Terraform runs in `hashicorp/terraform:1.15.9`. Cloud credentials and Terraform variables are forwarded by name to the tool container without writing an environment file.

<!--
==============================================================================
OCI CREDENTIAL CONTRACT
==============================================================================
-->

## OCI Credential File

Store one secret-file credential containing this JSON structure:

```json
{
  "tenancy_ocid": "ocid1.tenancy.example",
  "user_ocid": "ocid1.user.example",
  "fingerprint": "00:00:00:00",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
  "region": "region-1",
  "compartment_ocid": "ocid1.compartment.example"
}
```

The OCI resource validates this structure, installs OCI CLI `3.91.0` in a pinned `python:3.11.13-slim` execution container, writes a temporary root-only OCI configuration, and never prints the private key or optional Vault secret.

<!--
==============================================================================
OCI RUN COMMAND CONTRACT
==============================================================================
-->

## OCI Run Command

Targets use a JSON array with `name`, `instance_id`, and `arguments`. The selected lifecycle action is prepended automatically. When `RUN_COMMAND_VAULT_SECRET_NAME` is set, exactly one active current Vault secret is loaded and appended as the final protected argument.

The fully rendered command must remain at or below OCI's 4,096-byte inline payload limit. Each target is monitored until success, failure, cancellation, or timeout, and an optional output marker must be present before the target is accepted.

<!--
==============================================================================
DRY RUN AND MUTATION
==============================================================================
-->

## Dry Run And Mutation

Validation is the default action. Deployment pipelines run remote `validate`, then remote `dry-run`, then require Jenkins approval before remote `deploy`. Terraform similarly requires explicit `apply` and checksum approval. Compose deployment requires a non-empty `DEPLOY_SCRIPT`.

Release creation and backups also require approval. Jenkins should not be the only path capable of rebuilding the Jenkins controller; retain an external manual emergency workflow.

<!--
==============================================================================
GITHUB STATUS REPORTING
==============================================================================
-->

## GitHub Status

`githubStatus` posts to `continuous-integration/jenkins` by default. The GitHub credential needs commit-status write permission for each managed repository. Set the repository as `owner/name`; the step uses Jenkins' `GIT_COMMIT` and `BUILD_URL` values.

<!--
==============================================================================
CONSUMER EXAMPLES
==============================================================================
-->

## Examples

The `examples` directory contains Terraform, monitoring, and Jenkins controller Jenkinsfiles. Values are placeholders and contain no production domains, addresses, or cloud identifiers.

<!--
==============================================================================
LIBRARY VALIDATION
==============================================================================
-->

## Validation

Run the non-mutating local checks:

```bash
shellcheck resources/scripts/*.sh
bash resources/scripts/validate-library.sh
actionlint .github/workflows/validate.yml
```

CI also compiles every Groovy entrypoint with pinned `groovy:4.0.27-jdk21`.

<!--
==============================================================================
RELEASE PROCESS
==============================================================================
-->

## Release Process

1. Validate Bash, Groovy, workflows, and library contracts.
2. Merge through the protected default branch.
3. Run `releasePipeline` with a semantic version tag.
4. Approve immutable tag and GitHub release creation.
5. Update consumers to the new immutable version after validation.
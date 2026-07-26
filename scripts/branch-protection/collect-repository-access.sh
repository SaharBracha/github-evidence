#!/usr/bin/env bash
# Collects repository access and configuration: who/what can reach the
# repository (collaborators, teams, invitations, deploy keys, webhooks, the
# GitHub App installation) and how it is guarded (environments and their
# protection rules, Actions permissions, custom properties, vulnerability
# reporting). Secret VALUES are never requested; Actions secrets are recorded
# as name/timestamp metadata only, exactly as GitHub's API returns them.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../lib/github-api.sh
source "${SCRIPT_DIR}/../lib/github-api.sh"

: "${GH_OWNER:?GH_OWNER must be set}"
: "${GH_REPO:?GH_REPO must be set}"

repo_path="/repos/${GH_OWNER}/${GH_REPO}"

repository_section="$(gh_section_get "${repo_path}")"
collaborators_section="$(gh_section_get_paginated "${repo_path}/collaborators?affiliation=all")"
teams_section="$(gh_section_get_paginated "${repo_path}/teams")"
invitations_section="$(gh_section_get_paginated "${repo_path}/invitations")"
deploy_keys_section="$(gh_section_get_paginated "${repo_path}/keys")"
webhooks_section="$(gh_section_get_paginated "${repo_path}/hooks")"
installation_section="$(gh_section_get "${repo_path}/installation")"

environments_section="$(gh_section_get_paginated "${repo_path}/environments")"
environment_details="{}"
if [[ "$(printf '%s' "$environments_section" | jq -r '.status')" == "collected" ]]; then
  # The environments list endpoint wraps its array as {total_count, environments: [...]}.
  env_names="$(printf '%s' "$environments_section" | jq -r '.data.environments[]?.name')"
  while IFS= read -r env_name; do
    [[ -z "$env_name" ]] && continue
    encoded_env="$(jq -rn --arg e "$env_name" '$e | @uri')"
    detail_section="$(gh_section_get "${repo_path}/environments/${encoded_env}")"
    branch_policies_section="$(gh_section_get_paginated "${repo_path}/environments/${encoded_env}/deployment-branch-policies")"
    environment_details="$(jq -n \
      --argjson acc "$environment_details" \
      --arg name "$env_name" \
      --argjson detail "$detail_section" \
      --argjson branch_policies "$branch_policies_section" \
      '$acc + {($name): {detail: $detail, deployment_branch_policies: $branch_policies}}')"
  done <<< "$env_names"
fi

actions_permissions_section="$(gh_section_get "${repo_path}/actions/permissions")"
actions_workflow_permissions_section="$(gh_section_get "${repo_path}/actions/permissions/workflow")"
actions_selected_actions_section="$(gh_section_get "${repo_path}/actions/permissions/selected-actions")"
actions_variables_section="$(gh_section_get_paginated "${repo_path}/actions/variables")"
actions_secrets_section="$(gh_section_get_paginated "${repo_path}/actions/secrets")"
custom_properties_section="$(gh_section_get "${repo_path}/properties/values")"
private_vulnerability_reporting_section="$(gh_section_get "${repo_path}/private-vulnerability-reporting")"

jq -n \
  --argjson repository "$repository_section" \
  --argjson collaborators "$collaborators_section" \
  --argjson teams "$teams_section" \
  --argjson invitations "$invitations_section" \
  --argjson deploy_keys "$deploy_keys_section" \
  --argjson webhooks "$webhooks_section" \
  --argjson installation "$installation_section" \
  --argjson environments "$environments_section" \
  --argjson environment_details "$environment_details" \
  --argjson actions_permissions "$actions_permissions_section" \
  --argjson actions_workflow_permissions "$actions_workflow_permissions_section" \
  --argjson actions_selected_actions "$actions_selected_actions_section" \
  --argjson actions_variables "$actions_variables_section" \
  --argjson actions_secrets "$actions_secrets_section" \
  --argjson custom_properties "$custom_properties_section" \
  --argjson private_vulnerability_reporting "$private_vulnerability_reporting_section" \
  '{
    repository: $repository,
    collaborators: $collaborators,
    teams: $teams,
    invitations: $invitations,
    deploy_keys: $deploy_keys,
    webhooks: $webhooks,
    installation: $installation,
    environments: $environments,
    environment_details: $environment_details,
    actions_permissions: $actions_permissions,
    actions_workflow_permissions: $actions_workflow_permissions,
    actions_selected_actions: $actions_selected_actions,
    actions_variables: $actions_variables,
    actions_secrets: $actions_secrets,
    custom_properties: $custom_properties,
    private_vulnerability_reporting: $private_vulnerability_reporting
  }'

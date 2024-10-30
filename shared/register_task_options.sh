#!/bin/bash

# Required Arguments
# - ECS_TASK_DEF: task definition to update revision for

function build_register_task_options() {
  # create array of command options for register-task-definition command (on FARGATE)
  # global reg_options variable to be used as output
  local task_def
  local container_def

  task_def="${1}"
  container_def="${2}"

  # build register-task-definition command options in array
  reg_options=( --family "${ECS_TASK_DEF}" )
  reg_options+=( --task-role-arn "$(echo "${task_def}" | jq -r '.taskDefinition.taskRoleArn')" )
  reg_options+=( --execution-role-arn "$(echo "${task_def}" | jq -r '.taskDefinition.executionRoleArn')" )
  reg_options+=( --network-mode "$(echo "${task_def}" | jq -r '.taskDefinition.networkMode')" )
  reg_options+=( --container-definitions "${container_def}" )
  reg_options+=( --volumes "$(echo "${task_def}" | jq '.taskDefinition.volumes')" )
  reg_options+=( --placement-constraints "$(echo "${task_def}" | jq '.taskDefinition.placementConstraints')" )
  reg_options+=( --requires-compatibilities "$(echo "${task_def}" | jq -r '.taskDefinition.requiresCompatibilities')" )
  reg_options+=( --cpu "$(echo "${task_def}" | jq -r '.taskDefinition.cpu')" )
  reg_options+=( --memory "$(echo "${task_def}" | jq -r '.taskDefinition.memory')" )
  # include --ephemeral-storage option if available in template task definition
  template_ephemeral_storage="$(echo "${task_def}" | jq -r '.taskDefinition.ephemeralStorage')"
  if [ "$template_ephemeral_storage" != null ]; then
      reg_options+=( --ephemeral-storage "${template_ephemeral_storage}")
  fi
}
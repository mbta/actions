#!/bin/bash
set -e -u

# attempt to get the contents of the template task definition from ECS (for Terraform-built ECS services)
echo "Retrieving ${ECS_SERVICE}-template task definition..."
taskdefinition="$(aws ecs describe-task-definition --region "${AWS_REGION}" --task-definition "${ECS_SERVICE}-template")" \
  || echo "No template task definition was found."

# if no template exists, attempt to get task definition currently running on AWS (for legacy ECS services)
if [ -z "${taskdefinition}" ]; then
  echo "Retreiving current ${ECS_SERVICE} task definition..."
  taskdefinition=$(aws ecs describe-task-definition --region "${AWS_REGION}" --task-definition "${ECS_SERVICE}")
fi

# use retrieved task definition as basis for new revision, but replace image
echo "Updating container image to ${DOCKER_TAG}."
newcontainers="$(echo "${taskdefinition}" | \
  jq '.taskDefinition.containerDefinitions' | \
  jq --arg tag "${DOCKER_TAG}" 'map(.image="\($tag)")')"

# check to make sure the secrets are included in the new container definition
if (echo "${newcontainers}" | jq '.[0] | .secrets' | grep '^null$'); then
  echo "Error: The container definition is missing its 'secrets' block. Deploy cannot proceed."
  exit 1
fi

echo "Publishing new task definition."
aws ecs register-task-definition \
  --family "${ECS_SERVICE}" \
  --task-role-arn "$(echo "${taskdefinition}" | jq -r '.taskDefinition.taskRoleArn')" \
  --execution-role-arn "$(echo "${taskdefinition}" | jq -r '.taskDefinition.executionRoleArn')" \
  --network-mode "$(echo "${taskdefinition}" | jq -r '.taskDefinition.networkMode')" \
  --container-definitions "${newcontainers}" \
  --volumes "$(echo "${taskdefinition}" | jq '.taskDefinition.volumes')" \
  --placement-constraints "$(echo "${taskdefinition}" | jq '.taskDefinition.placementConstraints')" \
  --requires-compatibilities "$(echo "${taskdefinition}" | jq -r '.taskDefinition.requiresCompatibilities[]')" \
  --cpu "$(echo "${taskdefinition}" | jq -r '.taskDefinition.cpu')" \
  --memory "$(echo "${taskdefinition}" | jq -r '.taskDefinition.memory')"

newrevision="$(aws ecs describe-task-definition --task-definition "${ECS_SERVICE}" | \
  jq -r '.taskDefinition.revision')"

function task_count_eq {
    local tasks
    task_count=$(aws ecs list-tasks --region $AWS_REGION --cluster $ECS_CLUSTER --service $ECS_SERVICE| jq '.taskArns | length')
    [[ $task_count = "$1" ]]
}

function exit_if_too_many_checks {
  if [[ $checks -ge 60 ]]; then
    exit 1
  fi
  sleep 5
  checks=$((checks+1))
}

expected_count=$(aws ecs list-tasks --region $AWS_REGION --cluster $ECS_CLUSTER --service $ECS_SERVICE| jq '.taskArns | length')

aws ecs update-service --region $AWS_REGION --cluster $ECS_CLUSTER --service $ECS_SERVICE --task-definition $ECS_SERVICE:$newrevision
if  [[ $expected_count = "0" ]]; then
    echo Environment $ECS_CLUSTER:$ECS_SERVICE is not running!
    echo
    echo We updated the definition: you can manually set the desired instances to 1.
    exit 1
fi

checks=0
while task_count_eq $expected_count; do
    echo not yet started...
    exit_if_too_many_checks
done

checks=0
until task_count_eq $expected_count; do
    echo old task not stopped...
    exit_if_too_many_checks
done

#!/bin/bash
set -e -u

# uncomment to debug
# set -x

# Register a new ECS Task Definition using the new Docker Image
# Update the ECS Service with this new Task Definition
#
# This was based off of the deploy script in the mbta/actions/deploy-ecs
# action.
#
# Required Arguments
# - AWS_REGION: region this ecs cluster is deployed in
# - ECS_CLUSTER: ecs cluster for service being updated
# - ECS_SERVICE: ecs service containing task being updated
# - ECS_TASK_DEF: task definition to update revision for
# - DOCKER_TAG: tag for docker image to use in new task definition

# makes 'build_register_task_options' function available, produces 'reg_options' global var
. $(dirname $0)/../shared/register_task_options.sh
reg_options=() # returned as global by build_register_task_options

# set default region so we don't have to specify --region everywhere
export AWS_DEFAULT_REGION="${AWS_REGION}"

# get the contents of the template task definition from ECS 
echo "Retrieving ${ECS_TASK_DEF}-template task definition..."
taskdefinition="$(aws ecs describe-task-definition --task-definition "${ECS_TASK_DEF}-template")"

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

# this task uses fargate, so publish the new task definition
echo "Publishing new Task Definition."
build_register_task_options "${taskdefinition}" "${newcontainers}"
aws ecs register-task-definition "${reg_options[@]}"

# deploy the new task to our scheduled ecs task
#
# inspired by https://doylew.medium.com/updating-aws-ecs-task-definition-and-scheduled-tasks-using-aws-cli-commands-through-deployment-jobs-7cef82262236

# get the task definition arn for the new task definition
newtaskdefarn="$(aws ecs describe-task-definition --task-definition "${ECS_TASK_DEF}" | \
    jq -r '.taskDefinition.taskDefinitionArn')"
# get the events rule for triggering the scheduled task
eventsrule=$(aws events list-targets-by-rule --rule "run-${ECS_TASK_DEF}")
# update the events rule json with the new task def arn
echo $eventsrule | \
    jq '.Targets[0].EcsParameters.TaskDefinitionArn='\"${newtaskdefarn}\" > \
    tempEvents.json
# update the event on aws with temp json
aws events put-targets --rule "run-${ECS_TASK_DEF}" --cli-input-json file://tempEvents.json

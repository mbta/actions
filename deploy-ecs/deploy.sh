#!/bin/bash
set -e -u

# uncomment to debug
# set -x

# Update an ECS service and monitor its deployment status.
# h/t to this blog post for inspiration:
# https://medium.com/@aaron.kaz.music/monitoring-the-health-of-ecs-service-deployments-baeea41ae737

# required environment variables:
# - AWS_REGION
# - ECS_CLUSTER
# - ECS_SERVICE
# - ECS_TASK_DEF
# - DOCKER_TAG

# makes 'build_register_task_options' function available, produces 'reg_options' global var
. "$(dirname $0)"/../shared/register_task_options.sh
reg_options=() # returned as global by build_register_task_options

function check_deployment_complete() {
  # extract task counts and test whether they match the desired state
  local deployment_details
  local id
  local rollout_status
  local min_desired_count
  local desired_count
  local pending_count
  local running_count
  local failed_count

  deployment_details="${1}"

  id="$(echo "${deployment_details}" | jq -r '.id')"

  # get rollout state
  rollout_status="$(echo "${deployment_details}" | jq -r '.rolloutState // "COMPLETED"')"

  # check if 0 desiredCount is allowed
  min_desired_count=1
  if [ "${ALLOW_ZERO_DESIRED}" = true ]; then
    min_desired_count=0
  fi

  # get current task counts
  desired_count="$(echo "${deployment_details}" | jq -r '[.desiredCount, '"${min_desired_count}"' ] | max')"
  pending_count="$(echo "${deployment_details}" | jq -r '.pendingCount')"
  running_count="$(echo "${deployment_details}" | jq -r '.runningCount')"
  failed_count="$(echo "${deployment_details}" | jq -r '.failedTasks')"

  # print current id, status, and task counts
  printf \
    "id: %s, Status: %+12s, Running: %3d, Failed: %3d, Pending: %3d, Desired: %3d\n" \
    "${id}" \
    "${rollout_status}" \
    "${running_count}" \
    "${failed_count}" \
    "${pending_count}" \
    "${desired_count}"

  # ensure that AWS believes the deployment to be completed
  # and if the number of running tasks equals the number of desired tasks, then we're all set
  [[ "${rollout_status}" = "COMPLETED" ]] \
  && [[ "${pending_count}" -eq "0" ]] \
  && [[ "${running_count}" -eq "${desired_count}" ]]
}

# set default region so we don't have to specify --region everywhere
export AWS_DEFAULT_REGION="${AWS_REGION}"

# attempt to get the contents of the template task definition from ECS (for Terraform-built ECS services)
echo "Retrieving ${ECS_TASK_DEF}-template task definition..."
taskdefinition="$(aws ecs describe-task-definition --task-definition "${ECS_TASK_DEF}-template")" \
  || echo "No template task definition was found."

# if no template exists, attempt to get task definition currently running on AWS (for legacy ECS services)
if [ -z "${taskdefinition}" ]; then
  echo "Retrieving current ${ECS_TASK_DEF} task definition..."
  taskdefinition=$(aws ecs describe-task-definition --task-definition "${ECS_TASK_DEF}")
fi

# use retrieved task definition as basis for new revision, but replace image
echo "Updating container image to ${DOCKER_TAG}."
newcontainers="$(echo "${taskdefinition}" | \
  jq '.taskDefinition.containerDefinitions' | \
  jq --arg tag "${DOCKER_TAG}" 'map(.image="\($tag)")')"

# check to make sure the secrets are included in the new container definition
if [ "${REQUIRES_SECRETS}" = true ] && (echo "${newcontainers}" | jq '.[0] | .secrets' | grep '^null$'); then
  echo "Error: The container definition is missing its 'secrets' block. Deploy cannot proceed."
  exit 1
fi

echo "::group::Publishing new ${LAUNCH_TYPE} task definition."
if [ "${LAUNCH_TYPE}" = "FARGATE" ]; then
  build_register_task_options "${taskdefinition}" "${newcontainers}"
  aws ecs register-task-definition "${reg_options[@]}"
elif [ "${LAUNCH_TYPE}" = "EC2" ] || [ "${LAUNCH_TYPE}" = "EXTERNAL" ]; then
  aws ecs register-task-definition \
    --family "${ECS_TASK_DEF}" \
    --task-role-arn "$(echo "${taskdefinition}" | jq -r '.taskDefinition.taskRoleArn')" \
    --execution-role-arn "$(echo "${taskdefinition}" | jq -r '.taskDefinition.executionRoleArn')" \
    --container-definitions "${newcontainers}" \
    --volumes "$(echo "${taskdefinition}" | jq '.taskDefinition.volumes')" \
    --placement-constraints "$(echo "${taskdefinition}" | jq '.taskDefinition.placementConstraints')"
else
  echo "::endgroup::"
  echo "Error: expected 'FARGATE', 'EC2', or 'EXTERNAL' launch-type, got ${LAUNCH_TYPE}"
  exit 1
fi
echo "::endgroup::" # publishing task definition

newrevision="$(aws ecs describe-task-definition --task-definition "${ECS_TASK_DEF}" | \
  jq -r '.taskDefinition.revision')"

# redeploy the cluster
echo "::group::Updating service ${ECS_SERVICE} to use task definition ${newrevision}..."
aws ecs update-service --cluster="${ECS_CLUSTER}" --service="${ECS_SERVICE}" --task-definition "${ECS_TASK_DEF}:${newrevision}"
echo "::endgroup::"

echo "::group::Wait for the new cluster to stabilize"
deployment_finished=false
while [ "${deployment_finished}" = "false" ]; do
  # get the service details
  service_status="$(aws ecs describe-services --cluster="${ECS_CLUSTER}" --services="${ECS_SERVICE}")"
  # extract the details for the new deployment (status PRIMARY)
  new_deployment="$(echo "${service_status}" | jq -r '.services[0].deployments[] | select(.status == "PRIMARY")')"

  # check whether the new deployment is complete
  if check_deployment_complete "${new_deployment}"; then
    echo "::endgroup::"
    echo "Deployment complete."
    deployment_finished=true
  else
    # extract deployment id
    new_deployment_id="$(echo "${new_deployment}" | jq -r '.id')"
    # find any tasks that may have stopped unexpectedly
    # this should provide an array of arns (if any)
    # i.e. ("arn:aws:ecs:us-west-2:123456789012:task/a1b2c3d4-5678-90ab-cdef-11111EXAMPLE" "arn:aws:ecs:us-west-2:123456789012:task/a1b2c3d4-5678-90ab-cdef-22222EXAMPLE")
    mapfile -t stopped_tasks < <(aws ecs list-tasks --cluster "${ECS_CLUSTER}" --started-by "${new_deployment_id}" --desired-status "STOPPED" | jq -r '.taskArns[]')

    # count number of tasks in array
    stopped_task_count=${#stopped_tasks[@]}

    if [ "${stopped_task_count}" -gt "0" ]; then
      echo "::endgroup::"

      # if there are stopped tasks, print the reason they stopped and then exit
      stopped_reasons="$(aws ecs describe-tasks --cluster "${ECS_CLUSTER}" --tasks "${stopped_tasks[@]}" | jq -r '.tasks[].stoppedReason')"
      echo "The deployment failed because one or more containers stopped running. The reasons given were:"
      echo "${stopped_reasons}"
      exit 1
    fi
    # wait, then loop
    sleep 5
  fi
done
echo "::endgroup::"

echo "::group::confirm that the old deployment is torn down"
teardown_finished=false
while [ "${teardown_finished}" = "false" ]; do
  # get the service details
  service_status="$(aws ecs describe-services --cluster="${ECS_CLUSTER}" --services="${ECS_SERVICE}")"
  # extract the details for any old deployments (status ACTIVE)
  deployment="$(echo "${service_status}" | jq -r --compact-output '.services[0].deployments[] | select(.status == "ACTIVE")')"
  total_tasks=0

  # extract deployment id
  old_deployment_id="$(echo "${deployment}" | jq -r '.id')"
  # if the previous deployment is already inactive, exit now
  if [ -z "${old_deployment_id}" ]; then
    echo "No active previous deployments found."
    break
  fi
  # count tasks associated with the old deployment that are still running
  running_task_count="$(aws ecs list-tasks --cluster "${ECS_CLUSTER}" --started-by "${old_deployment_id}" --desired-status "RUNNING" | jq -r '.taskArns | length')"
  total_tasks=$((total_tasks+running_task_count))

  echo "Old tasks still running: ${total_tasks}"
  # if no running tasks, break
  if [ "$total_tasks" -eq "0" ]; then
    break
  else
    echo "Waiting for old tasks to be stopped..."
    sleep 5
  fi
done
echo "::endgroup::"

echo "Done."

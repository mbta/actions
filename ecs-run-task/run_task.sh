#!/bin/bash
set -e -u

# Run an ECS Task from the provided CLUSTER and SERVICE
#
# This actions is generally used for ad-hoc launching of ECS tasks that are scheduled with EventBridge
# Will launch 1 instance of latest SERVICE task 
# with launch-type and network-configuration found in describe-services call
#
# This action requires the GHA IAM role to have the following permissions:
# ecs:RunTask on SERVICE task-definition
# ecs:DescribeServices on CLUSTER service

# required environment varialbes
# - AWS_REGION
# - CLUSTER
# - SERVICE

# Get the service description for the task.
echo "Retrieving service description for SERVICE:${SERVICE} in CLUSTER:${CLUSTER}"
service_description=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --service $SERVICE \
  --query services[0])

launch_type="$(echo "${service_description}" | jq -r '.launchType')"
net_config="$(echo "${service_description}" | jq -r '.networkConfiguration')"

echo "Running latest version of '${SERVICE}' task, in '${CLUSTER}' cluster."
echo "launch-type=${launch_type}"
echo "network-configuration=${net_config}"

# Run the ECS task
aws ecs run-task \
  --cluster $CLUSTER \
  --task-definition $SERVICE \
  --launch-type "${launch_type}" \
  --count 1 \
  --network-configuration "${net_config}"

#!/bin/bash

# run task from task definition
task_run=$(aws ecs run-task --task-definition "${ECS_TASK_DEFINITION}" --cluster "${ECS_CLUSTER}" --launch-type FARGATE --network-configuration "${ECS_TASK_NETWORK_CONFIGURATION}" --overrides "${ECS_TASK_OVERRIDES}")
# get unique task arn
task_arn=$(echo $task_run | jq '.tasks[0].taskArn')

# keep track of if finished, or timed out
finished=false
timed_out=false
time=0
# continously check for completion until either finished or timed out
while [[ "${finished}" == "false" && "${timed_out}" == "false" ]] ; do

  # get the latest state of the task
  task_description=$(aws ecs describe-tasks --cluster "${ECS_CLUSTER}" --tasks [$task_arn])
  # get the latest status
  task_status=$(echo $task_description | jq '.tasks[0].lastStatus')

  # check if in a completed state
  # see https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle.html
  if [[ "$task_status" == "\"DEACTIVATING\"" || "$task_status" == "\"STOPPING\"" || "$task_status" == "\"DEPROVISIONING\"" || "$task_status" == "\"STOPPED\"" ]] ; then
    finished=true
  # allow for 10 minutes before timing out
  elif [[ $time -gt 600 ]] ; then
    timed_out=true
  # sleep for 5 seconds before checking status again
  else
    sleep 5
    ((time=$time+5))
  fi

done

# when timed out, exit with an error code and the last task description
if [[ "${timed_out}" == "true" ]] ; then
  echo 'Run Task failed!'
  echo '----------------------------------------'
  echo $task_description
  echo '----------------------------------------'
  exit 1
fi

# done
echo 'Run Task successful!'

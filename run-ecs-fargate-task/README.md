
# (ECS) Run Task

This action will run your ECS Task Definition as a task on Fargate. The action will wait until the task has reached a completion state before exiting. If a completion state is not reached in 10 minutes (timeout), the action will exit with an error, printing out the last status (JSON).

### Inputs

* **aws_access_key_id**: (Required) Will be passed to GitHub Actions environment as the AWS_ACCESS_KEY_ID environment variable to be used in AWS CLI commands.
* **aws_secret_access_key**: (Required) Will be passed to GitHub Actions environment as the AWS_SECRET_ACCESS_KEY environment variable to be used in AWS CLI commands.
* **aws_default_region**: (Required) Will be passed to GitHub Actions environment as the AWS_DEFAULT_REGION environment variable to be used in AWS CLI commands (from `aws configure`).
* **ecs_cluster**: (Required) Cluster ARN to be used for running the task (ex. `arn:aws:ecs:{aws-region}:{aws-account-id}:cluster/{cluster-name}`). 
* **ecs_task_definition**: (Required) Task Definition ARN to base the task on (ex. `arn:aws:ecs:{aws-region}:{aws-account-id}:task-definition/{task-definition-name}`).
* **ecs_task_network_configuration**: (Required) Network settings that the task will be run with. See [this](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-configure-network.html) for more information.
* **ecs_task_overrides**: Override settings that the task will be run with. See [this](https://docs.aws.amazon.com/cli/latest/reference/ecs/run-task.html) for more information.


### Dependecies

* **awscli** Satisfied by GitHub Actions.
* **jq** Satisfied by GitHub Actions.

# Reusable workflows

This folder collects our [reusable workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows).

## deploy-ecs.yml

Example usage, in **my_app/.github/workflows/deploy-ecs.yml**:

```yml
name: Deploy to ECS

on:
  workflow_dispatch:
    inputs:
      environment:
        type: environment
        required: true
        default: dev
  push:
    branches: master

jobs:
  call-workflow:
    uses: mbta/actions/workflows/deploy-ecs@main
    with:
      app-name: my-app
      environment: ${{ github.event.inputs.environment || 'dev }}
    secrets:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      docker-repo: ${{ secrets.DOCKER_REPO }}
      slack-webhook: ${{ secrets.SLACK_WEBHOOK }}
```

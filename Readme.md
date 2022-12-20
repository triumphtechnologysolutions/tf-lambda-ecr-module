# Deploy Dockerized Lambda with Terraform

This is a Terraform module that deploys a Dockerized Lambda function to AWS using ECR, EFS and Lambda.


## Inputs

| Name            | Description                                                                   |  Type  | Default | Required |
| --------------- | ----------------------------------------------------------------------------- | :----: | :-----: | :------: |
| repository_name | The name of the ECR repository to which the Docker image should be pushed.    | string |    -    |   yes    |
| org             | The name of the organization to which the ECR repository should be pushed.    | string |    -    |   yes    |
| env             | The environment of the project. Example: dev, test, prod.                     | string |    -    |   yes    |
| vpc_id          | The ID of the VPC to which the Lambda function should be attached.            | string |    -    |   yes    |
| subnet_ids      | A list of subnet IDs to which the Lambda function and EFS should be attached. |  list  |    -    |   yes    |
| vpc_cidr        | The CIDR block of the VPC to which the EFS file sistem should be attached.    | string |    -    |   yes    |

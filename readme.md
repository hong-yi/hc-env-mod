# Health Checker Infrastructure as Code

This repository contains the Terraform code that will provision the environment resources required to run the health checker application. 

## Usage

You can use it as a module to provision the resources with the following variables:

| Variable Name    | Description                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `project_name`   | name of the project (e.g health_checker)                                                     |
| `vpc_cidr_block` | address space that you want to use. take note the address space will be split into 2 subnets |

This will produce an output with 3 variables that you will need for the application infrastructure part. You can copy and paste the outputs into the module for the application infrastructure code.

## Example

An example of using this module is provided:

```hcl
module "health_checker_infra" {
  source         = "https://github.com/hong-yi/health-checker-infra.git"
  project_name   = "healthchecker"
  vpc_cidr_block = "172.16.0.0/23"
}

output "project_name" {
  value = module.health_checker_infra.project_name
}

output "vpc_id" {
  value = module.health_checker_infra.vpc_id
}

output "subnet_ids" {
  value = module.health_checker_infra.subnet_ids
}
```

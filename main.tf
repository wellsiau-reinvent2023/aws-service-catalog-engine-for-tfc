# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  cloud {
    organization = "aws-reinvent-demo"
    workspaces {
      name = "tfc_re_bootstrap"
    }
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.45.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      "Projects" = "aws-service-catalog-engine"
    }
  }
}

data "aws_secretsmanager_secret_version" "tfe_token_secret" {
  secret_id = "terraform-cloud-credentials-for-bootstrap"
}

provider "tfe" {
  hostname = var.tfc_hostname
  token    = data.aws_secretsmanager_secret_version.tfe_token_secret.secret_string
}

# This module provisions the Terraform Cloud Reference Engine. If you would like to provision the Reference Engine
# without the example product, you can use this module in your own terraform configuration/workspace.
module "terraform_cloud_reference_engine" {
  source = "./engine"

  tfc_organization                 = var.tfc_organization
  tfc_team                         = var.tfc_team
  tfc_aws_audience                 = var.tfc_aws_audience
  tfc_hostname                     = var.tfc_hostname
  cloudwatch_log_retention_in_days = var.cloudwatch_log_retention_in_days
  enable_xray_tracing              = var.enable_xray_tracing
  token_rotation_interval_in_days  = var.token_rotation_interval_in_days
  terraform_version                = var.terraform_version
}

# Creates an AWS Service Catalog Portfolio to house the example product
resource "aws_servicecatalog_portfolio" "portfolio" {
  name          = "TFC Example Portfolio"
  description   = "Example Portfolio created via AWS Service Catalog Engine for TFC"
  provider_name = "HashiCorp Examples"
}

# An example product
module "example_product" {
  source = "./example-product"

  # ARNs of Lambda functions that need to be able to assume the IAM Launch Role
  parameter_parser_role_arn  = module.terraform_cloud_reference_engine.parameter_parser_role_arn
  send_apply_lambda_role_arn = module.terraform_cloud_reference_engine.send_apply_lambda_role_arn

  # AWS Service Catalog portfolio you would like to add this product to
  service_catalog_portfolio_ids = [aws_servicecatalog_portfolio.portfolio.id]

  # Variables for authentication to AWS via Dynamic Credentials
  tfc_hostname     = module.terraform_cloud_reference_engine.tfc_hostname
  tfc_organization = module.terraform_cloud_reference_engine.tfc_organization
  tfc_provider_arn = module.terraform_cloud_reference_engine.oidc_provider_arn

}

# Stores module outputs to SSM parameter 
resource "aws_ssm_parameter" "parameter_parser_role_arn" {
  name  = "/tfc/tre/parameter_parser_role_arn"
  type  = "String"
  value = module.terraform_cloud_reference_engine.parameter_parser_role_arn
}

resource "aws_ssm_parameter" "send_apply_lambda_role_arn" {
  name  = "/tfc/tre/send_apply_lambda_role_arn"
  type  = "String"
  value = module.terraform_cloud_reference_engine.send_apply_lambda_role_arn
}

resource "aws_ssm_parameter" "tfc_hostname" {
  name  = "/tfc/tre/tfc_hostname"
  type  = "String"
  value = module.terraform_cloud_reference_engine.tfc_hostname
}

resource "aws_ssm_parameter" "tfc_organization" {
  name  = "/tfc/tre/tfc_organization"
  type  = "String"
  value = module.terraform_cloud_reference_engine.tfc_organization
}

resource "aws_ssm_parameter" "oidc_provider_arn" {
  name  = "/tfc/tre/oidc_provider_arn"
  type  = "String"
  value = module.terraform_cloud_reference_engine.oidc_provider_arn
}

# Stores the Terraform Cloud variable sets
resource "tfe_project" "service_catalog" {
  organization = var.tfc_organization
  name = var.tfc_team
}

resource "tfe_variable_set" "tfe_var_set" {
  name         = "Dynamic Cred Variable Sets DOP315"
  description  = "AWS dynamic credentials applied to service catalog workspaces."
  organization = var.tfc_organization
}

resource "tfe_project_variable_set" "tfc_gcp_oidc_var_set" {
  project_id      = tfe_project.service_catalog.id
  variable_set_id = tfe_variable_set.tfe_var_set.id
}

resource "tfe_variable" "enable_aws_provider_auth" {
  variable_set_id = tfe_variable_set.tfe_var_set.id

  key      = "TFC_AWS_PROVIDER_AUTH"
  value    = "true"
  category = "env"

  description = "Enable the Workload Identity integration for AWS."
}

resource "tfe_variable" "tfc_aws_role_arn" {
  variable_set_id = tfe_variable_set.tfe_var_set.id

  key      = "TFC_AWS_RUN_ROLE_ARN"
  value    = module.terraform_cloud_reference_engine.tfc_dynamic_provider_role_arn
  category = "env"

  description = "The AWS role arn runs will use to authenticate."
}

variable "repository_name" {
  type        = string
  description = "The name of the repository"
}

variable "region" {
  type        = string
  default     = "us-east-2"
  description = "The AWS region"
}

variable "org" {
  type        = string
  description = "The organization name"
}

variable "env" {
  type        = string
  description = "The environment name"
}

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR of the VPC"
}

variable "private_subnets" {
  type        = list(string)
  description = "The list of private subnets"
}
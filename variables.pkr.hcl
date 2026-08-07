variable "region" {
  type        = string
  description = "AWS region where the AMI will be built."
  default     = "us-east-1"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type used during the build."
  default     = "t4g.small"
}

variable "ami_name_prefix" {
  type        = string
  description = "Prefix for the resulting AMI name."
  default     = "red-k3s"
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags applied to the AMI and its snapshots."
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the build instance will be launched."
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the build instance. Must have a route to the internet (public subnet, or private with NAT)."
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM instance profile attached to the build instance. Must include AmazonSSMManagedInstanceCore. Created in red-infra as PackerBuildRole."
}

variable "associate_public_ip_address" {
  type        = bool
  description = "Whether to assign a public IP to the build instance. Set true for public subnets, false for private subnets with NAT."
  default     = true
}

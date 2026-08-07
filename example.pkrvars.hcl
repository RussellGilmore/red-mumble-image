region        = "us-east-1"
instance_type = "t4g.small"

vpc_id    = "vpc-xxxxxxxxxxxxxxxxx"
subnet_id = "subnet-xxxxxxxxxxxxxxxxx"

iam_instance_profile = "PackerBuildRole"
# Network resources to get around this cost money :(
associate_public_ip_address = true

extra_tags = {
  Owner   = "Russell Gilmore"
  Project = "red-space"
}

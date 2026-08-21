# Copy this to a real vars file (e.g. build.auto.pkrvars.hcl, which is
# gitignored) and fill in the values for your account. None of these are
# secrets, but the file is per-environment so it stays out of source control.

# AWS region to build in.
region = "us-east-1"

# Build instance type (Graviton/arm64). t4g.small is plenty for a bake.
instance_type = "t4g.small"

# Prefix for the resulting AMI name. Final name is <prefix>-<timestamp>.
ami_name_prefix = "red-mumble"

# Informational tag for traceability. The distro package is what actually
# gets installed regardless of this value.
mumble_version = "distro"

# Root volume size (GB) for the build and resulting AMI.
root_volume_size = 16

# --- Build networking ---
# The build instance launches here. The subnet MUST have outbound internet
# (public subnet with an IGW, or private with a NAT) so apt/certbot packages
# can download during the bake.
vpc_id    = "vpc-xxxxxxxxxxxxxxxxx"
subnet_id = "subnet-xxxxxxxxxxxxxxxxx"

# Set true for a public subnet, false for a private subnet with NAT.
associate_public_ip_address = true

# --- Build IAM ---
# Instance profile for the build instance. MUST include
# AmazonSSMManagedInstanceCore (Packer connects via Session Manager).
# This is the PackerBuildRole you created in red-infra for the k3s image.
iam_instance_profile = "PackerBuildRole"

# --- Optional ---
# Extra tags applied to the AMI and its snapshots.
extra_tags = {
  Project = "red-space"
  Purpose = "mumble"
}

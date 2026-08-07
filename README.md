# Red Mumble Image

Packer configuration that builds an AWS AMI containing K3s and cert-manager,
ready for single-node cluster bootstrap via EC2 user_data.

## Overview

## Components

## Prerequisites

-   Packer >= 1.14.0
-   AWS credentials configured (env vars, shared config, or instance profile)
-   Permissions to create AMIs, snapshots, key pairs, security groups, and EC2
    instances in the target region

## Build

```bash
packer init .
packer fmt -check .
packer validate -var-file=example.pkrvars.hcl .
packer build -var-file=example.pkrvars.hcl .
```

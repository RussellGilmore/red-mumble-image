# Red Mumble Image

Packer configuration that builds a public AWS AMI running a
[Mumble](https://www.mumble.info/) (Murmur) voice server with automatic TLS via
Let's Encrypt DNS-01 challenges through Route53.

## Overview

This image bakes in everything a Mumble server needs and defers all
domain-specific and secret configuration to first boot via cloud-init. The
resulting AMI is **public-safe and domain-agnostic** — it contains no
certificates, keys, domain names, or passwords. Launch it for any domain by
supplying values through EC2 user-data.

Key design points:

-   **Ubuntu 26.04 LTS (Resolute), arm64/Graviton** base, rebuilt from the
    newest Canonical image at each bake.
-   **TLS via DNS-01, not HTTP-01.** certbot obtains and renews certificates by
    writing TXT records to Route53 using the instance's IAM role — no port 80,
    no stored AWS keys, no inbound reachability requirement for cert issuance.
-   **SSM-only access.** No SSH key pair; reach the instance through AWS Session
    Manager. IMDSv2 required, root volume encrypted.
-   **Unattended renewal.** certbot's systemd timer renews the certificate and a
    deploy-hook redeploys it to Mumble automatically — no manual cert copying.
-   **Runtime configuration.** Domain, Let's Encrypt email, SuperUser password,
    welcome message, and server password are all injected at first boot.

## Components

Baked into the image:

-   `mumble-server` (installed, disabled until first boot obtains a cert)
-   `certbot` and `python3-certbot-dns-route53`
-   A certbot deploy-hook that places renewed certs where Mumble can read them
-   A Mumble config template (cert paths fixed; runtime values slotted in)
-   A first-boot script (`/usr/local/sbin/mumble-first-boot.sh`) driven by
    cloud-init
-   certbot renewal timer (enabled, dormant until a cert exists)

## Prerequisites

-   Packer >= 1.14.0
-   AWS credentials configured (env vars, shared config, or instance profile)
-   A build VPC/subnet with outbound internet access
-   An IAM instance profile for the build with `AmazonSSMManagedInstanceCore`
    (Packer connects via Session Manager)

## Build

Copy the example vars file, fill in your build networking, and build:

```bash
cp example.pkrvars.hcl build.auto.pkrvars.hcl   # gitignored; edit values
packer init .
packer fmt -check .
packer validate .
packer build .
```

The build prints the resulting AMI ID on completion. See `variables.pkr.hcl` for
all available build variables.

## Runtime configuration contract

At first boot, cloud-init (from the instance's user-data) must write
`/etc/red-mumble/first-boot.env` and invoke the first-boot script. The env file
supports:

| Variable                    | Required | Description                                                                                              |
| --------------------------- | :------: | -------------------------------------------------------------------------------------------------------- |
| `MUMBLE_DOMAIN`             |   yes    | FQDN for the server; also the cert domain.                                                               |
| `LE_EMAIL`                  |   yes    | Let's Encrypt registration email.                                                                        |
| `MUMBLE_SUPERUSER_PASSWORD` |   yes    | Mumble SuperUser password (hashed into the DB on first start, then stripped from disk).                  |
| `MUMBLE_WELCOME_TEXT`       |    no    | Welcome message shown to clients. Supports Mumble HTML (`<br />`, `<b>`). Defaults to a generic message. |
| `MUMBLE_SERVER_PASSWORD`    |    no    | Password clients must enter to join. Empty means an open server.                                         |

The instance's IAM role must permit Route53 record changes on the domain's
hosted zone for the DNS-01 challenge.

## Deploying with red-instance

This image pairs with the
[terraform-aws-red-instance](https://github.com/RussellGilmore/terraform-aws-red-instance)
module (>= v2.2.0), which provides the `enable_route53_policy` and `user_data`
inputs this image needs.

A cloud-config user-data template (`mumble-user-data.yaml.tftpl`) writes the env
file and runs first-boot:

```yaml
#cloud-config
write_files:
    - path: /etc/red-mumble/first-boot.env
      owner: root:root
      permissions: "0600"
      content: |
          MUMBLE_DOMAIN=${mumble_domain}
          LE_EMAIL=${le_email}
          MUMBLE_SUPERUSER_PASSWORD="${superuser_password}"
          MUMBLE_WELCOME_TEXT="${welcome_text}"
          MUMBLE_SERVER_PASSWORD="${server_password}"

runcmd:
    - /usr/local/sbin/mumble-first-boot.sh
```

And the module call:

```hcl
module "mumble" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-instance.git?ref=v2.2.0"

  project_name  = "red-space"
  instance_name = "Mumble"

  instance_type = "t4g.micro"
  ami_name      = "red-mumble-*"        # matches the Packer ami_name_prefix
  ami_owner     = var.mumble_ami_owner  # your account ID (you built the AMI)
  volume_size   = 16

  # Standalone: the module provisions its own public VPC.
  create_vpc        = true
  availability_zone = "us-east-1f"
  allocate_eip      = true

  # Mumble uses 64738 TCP + UDP. No SSH (SSM-only), no port 80 (DNS-01).
  ingress_rules = [
    {
      description = "Mumble TCP"
      from_port   = 64738
      to_port     = 64738
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "Mumble UDP"
      from_port   = 64738
      to_port     = 64738
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  # Route53 for DNS-01 cert issuance and renewal.
  enable_route53_policy = true
  route53_zone_id       = var.mumble_zone_id

  # Rendered user-data carrying domain and secrets.
  user_data = templatefile("${path.module}/mumble-user-data.yaml.tftpl", {
    mumble_domain      = "mumble.example.org"
    le_email           = var.le_email
    superuser_password = var.mumble_superuser_password
    welcome_text       = var.mumble_welcome_text
    server_password    = var.mumble_server_password
  })

  # Public DNS A record for the server.
  enable_public_dns = true
  apex_domain       = "example.org"
  dns_name          = "mumble.example.org"
}
```

Secret values (`le_email`, `mumble_superuser_password`,
`mumble_server_password`) are supplied via Terraform variables sourced from a
local, gitignored `.env` (as `TF_VAR_*`) at apply time, so they never enter
source control.

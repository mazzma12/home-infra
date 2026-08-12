# home-infra

[![Lint](https://github.com/mazzma12/home-infra/actions/workflows/lint.yml/badge.svg)](https://github.com/mazzma12/home-infra/actions/workflows/lint.yml)

Terraform for a single Oracle Cloud **Always Free** ARM box, plus a retry loop that
keeps trying until Oracle actually has capacity.

| | |
|---|---|
| Shape | `VM.Standard.A1.Flex` — 2 OCPU / 12 GB, Ampere Altra (aarch64) |
| Image | Ubuntu 24.04 LTS aarch64 |
| Storage | 200 GB boot volume (the entire free block-storage pool) |
| Region | `eu-paris-1` |
| Cost | €0 — a $1 budget alert acts as a tripwire |

## Why the retry loop

A1.Flex free-tier capacity is heavily oversubscribed, so `terraform apply` usually
fails with **"Out of host capacity"**. `deploy.sh` is designed to be run repeatedly
from cron until one attempt lands. That loop is the point of this repo.

It exits immediately once the instance is in state, so leaving it in cron is safe.

## Prerequisites

- Terraform ≥ 1.4 and an OCI account with a configured `~/.oci/config` (profile `DEFAULT`)
- An SSH public key at `~/.ssh/oracle.pub` (override with `var.ssh_public_key_path`)
- [`apprise`](https://github.com/caronc/apprise) on `PATH`, and `~/.config/apprise/.env`
  exporting `APPRISE_TELEGRAM_URL` — used for success/failure notifications
- `terraform/terraform.tfvars` with your budget-alert email — copy from
  `terraform.tfvars.example`. It is gitignored and auto-loaded, so cron picks it up.

## Usage

```bash
terraform -chdir=terraform init
./deploy.sh                       # one sweep; safe to re-run
```

Under cron, every 20 minutes:

```cron
*/20 * * * * /path/to/home-infra/deploy.sh >> ~/.logs/home-infra.log 2>&1
```

Standalone looping instead of cron:

```bash
ATTEMPTS=100 SLEEP_SECONDS=60 ./deploy.sh
```

## Connecting

On success the Telegram notification includes a paste-ready SSH stanza. To print it
again:

```bash
terraform -chdir=terraform output -raw ssh_config
```

```
Host oracle
    HostName <public ip>
    User ubuntu
    IdentityFile ~/.ssh/oracle
    IdentitiesOnly yes
```

## Gotchas

- **State is local and untracked.** `terraform.tfstate` lives only on the host that
  applies, and is gitignored. Losing it means losing the ability to manage the instance.
  There is no remote backend yet.
- **Changing the image destroys the instance.** The OCI provider misreports this as an
  in-place update ([#2133](https://github.com/oracle/terraform-provider-oci/issues/2133)),
  so a `terraform_data` + `replace_triggered_by` forces an honest plan. Replacement gives
  up the capacity slot with no guarantee of getting it back.
- **`var.ssh_user` must match the image** — `ubuntu` for Canonical, `opc` for Oracle Linux.
- **Don't split the 200 GB.** It is one pool shared by boot and block volumes. A smaller
  root loses IOPS proportionally (60 IOPS/GB), and OCI volumes can never be shrunk.
- **Always Free reclaims idle instances** under 20% p95 CPU over 7 days.
- **The region is permanent.** Your home region is chosen at account creation and cannot
  be changed afterwards — there is no migration path short of a new tenancy. Capacity
  varies a lot between regions (Marseille often has A1 where Paris does not), so this is
  the single highest-leverage decision at signup, and it is unfixable later.

## Development

```bash
pre-commit run --all-files   # terraform fmt + validate, ruff, pyright
tflint --chdir=terraform --minimum-failure-severity=error
```

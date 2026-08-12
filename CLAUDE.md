# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What this repo is

Terraform for a single OCI Always Free ARM instance (`VM.Standard.A1.Flex`,
2 OCPU / 12 GB / 200 GB boot, Ubuntu 24.04 aarch64, `eu-paris-1`), plus `deploy.sh`,
which retries the apply and notifies Telegram.

A1.Flex capacity is scarce, so apply usually fails with "Out of host capacity".
`deploy.sh` is built to run repeatedly from cron until one lands — that retry loop
*is* the point of the repo.

## Commands

```bash
terraform -chdir=terraform fmt|plan|apply
tflint --chdir=terraform --minimum-failure-severity=error  # what CI runs
pre-commit run --all-files                                 # incl. terraform_fmt/validate
uv sync && uv run pytest                                   # no Python source yet
```

## Key facts

- **Auth**: the provider reads `~/.oci/config`, profile `DEFAULT`. No credentials
  live in this repo; a bad `~/.oci/config` is the usual cause of provider errors.
- **State is local and untracked**, sitting on whichever host applies. The instance
  is currently provisioned. There is no remote backend — adding one is the open item.
- **Free tier ceiling** (halved by Oracle in 2026): 1,500 OCPU-h + 9,000 GB-h/month,
  i.e. 2 OCPU / 12 GB running 24/7. Block storage is a single 200 GB pool shared by
  boot *and* block volumes, spent entirely on the boot volume. Do not split off a data
  volume: Balanced volumes give 60 IOPS/GB, so a smaller root loses IOPS proportionally,
  and OCI volumes can only grow, never shrink.
- **Changing `image_id` is destructive.** The provider plans a bogus in-place update
  then fails at apply (oracle/terraform-provider-oci#2133); `terraform_data.image_id`
  + `replace_triggered_by` forces honest replacement. Replacing releases the capacity
  slot with no guarantee of reacquiring it.
- **`var.ssh_user` must track `var.image_id`**: `ubuntu` for Canonical images, `opc`
  for Oracle Linux. Oracle Linux also strands everything past 30 GB until `oci-growfs`
  runs; Ubuntu's images `growpart` the root filesystem on first boot.
- **The SSH key** is read from `var.ssh_public_key_path` (`~/.ssh/oracle.pub`) via
  `file()`, so that file must exist on the applying host. `terraform validate` does
  not evaluate `file()`, which is why CI passes without it.
- **The AD is picked by index**, not name: `var.ad_index` wraps modulo the AD count
  (`eu-paris-1` has one). `deploy.sh` bails early if the instance is already in state,
  since `availability_domain` is ForceNew and a sweep would replace a live instance.
- **`deploy.sh` resolves its own directory**, so cron can run it from any cwd. It sources
  `~/.config/apprise/.env` for `APPRISE_TELEGRAM_URL` — that URL embeds a bot token, never
  echo it. On success it sends the `ssh_config` output as a paste-ready stanza; on failure,
  captured stderr. `ATTEMPTS`, `AD_COUNT`, `SLEEP_SECONDS` override the single-sweep default.
- **Capacity, not quota, is the blocker.** Oracle's advice is Pay As You Go — larger
  pool, no charge below the free limits, exempt from idle reclamation (Always Free
  reclaims instances under 20% p95 CPU over 7 days). `budget.tf` holds a $1 budget
  alert as the tripwire. Home region is fixed at signup and irreversible.
- **`main.tf` began as a console stack export**, hence the verbose agent/plugin block.
  Subnet and image OCIDs are region-scoped: both must change with `var.region`.
- **CI** runs tflint (errors only, so warnings pass), `terraform fmt -check` and
  `validate -backend=false`. It triggers only on push/PR to `main`. `main.tf` emits one
  tflint warning: missing `terraform required_version`.

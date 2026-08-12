# Plan: move Terraform state to OCI Object Storage

**Status:** not started. Written 2026-08-12.

## Why

State currently lives only at `terraform/terraform.tfstate` on the Mac that runs cron.
Losing that file means losing the ability to manage or destroy the instance — and
reacquiring A1.Flex capacity is the hard part, so an orphaned instance is expensive to
recover from. Committing state to git is not the fix: it contains the budget-alert email,
the tenancy OCID and the SSH public key, it churns on every plan, and git offers no
locking against a cron apply.

## Approach: the native `oci` backend

Terraform **v1.12+** ships a first-party `oci` backend. The older S3-compatibility route
is deprecated and should not be used — it needs a Customer Secret Key (a second, separate
credential to store), whereas the native backend reuses `~/.oci/config`.

Locking is built in: the backend uses `If-None-Match: *` against Object Storage, creating
lock objects in the same bucket during plan/apply/destroy. No DynamoDB equivalent, no
`use_lockfile` flag.

Local Terraform is **1.15.5**, so this is available today.

### Known values

| | |
|---|---|
| Namespace | `axe2rnesumka` |
| Region | `eu-paris-1` |
| Bucket | `terraform-state` (does not exist yet — no buckets in the tenancy) |
| Auth | `~/.oci/config`, profile `DEFAULT` |
| Free tier | Object Storage 20 GB; state is ~15 KB |

## Steps

1. **Stop cron.** A `deploy.sh` run mid-migration would apply against half-moved state.
   Verify with `crontab -l` and confirm no `terraform` process is running.
   → verify: `pgrep -fl terraform` returns nothing.

2. **Back up local state**, outside the repo, before touching anything.
   → verify: the copy exists and `serial` matches `terraform/terraform.tfstate`.

3. **Create the bucket out-of-band.** It cannot be managed by the config it stores state
   for. Enable versioning so a bad write is recoverable.
   ```bash
   oci os bucket create --name terraform-state --compartment-id <tenancy> --versioning Enabled
   ```
   → verify: `oci os bucket get --name terraform-state` returns `"versioning": "Enabled"`.

4. **Add the backend block** to `terraform/main.tf`:
   ```hcl
   terraform {
     backend "oci" {
       bucket              = "terraform-state"
       namespace           = "axe2rnesumka"
       key                 = "home-infra/terraform.tfstate"
       region              = "eu-paris-1"
       config_file_profile = "DEFAULT"
     }
   }
   ```

5. **Migrate**: `terraform -chdir=terraform init -migrate-state`, answering `yes`.
   → verify: `oci os object list --bucket-name terraform-state` shows the key, and
   `terraform state list` returns the same 5 resources as before.

6. **Prove locking works.** Start a long plan in one shell, run another concurrently.
   → verify: the second fails with a state-lock error, not a silent double-write.

7. **Fix `deploy.sh` for the cron host.** Its `terraform init` line is currently commented
   out. After a backend change, every command fails with "Backend initialization required"
   until `init` runs once. Either run it manually on the host or uncomment the line —
   deciding which is part of this task, since an uncommented `init` runs on every cron tick.
   → verify: run `./deploy.sh` as cron would (empty env, `env -i`) and confirm it exits 0
   with "Instance already provisioned".

8. **Re-enable cron**, then update `README.md` and `CLAUDE.md` (both currently state that
   state is local and untracked, and list a remote backend as the open item).

9. **Delete the local state file** only after a full cron cycle has succeeded against the
   remote backend.

## Risks

- **Migration during a cron tick** is the main hazard — mitigated by step 1.
- **Silent cron failure.** If the backend is misconfigured, every run fails. `deploy.sh`
  notifies on failure, so this surfaces via Telegram rather than silently, but the
  instance would be unmanaged until fixed.
- **Bucket deletion is unrecoverable** without versioning; hence step 3.
- **Network dependency.** Applies now require reaching Object Storage. Offline, cron fails.
- **The bucket is not in Terraform.** It must be documented as manually created, or it
  will confuse a future reader who finds no resource for it.

## Rollback

Remove the `backend` block, run `terraform init -migrate-state` to pull state back to
local, or restore the step-2 backup. Keep that backup until the remote path has run
unattended for a few days.

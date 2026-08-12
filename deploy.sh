#!/bin/bash
set -uo pipefail

export OCI_CONFIG_FILE="$HOME/.oci/config"
export OCI_PROFILE="DEFAULT"
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin" # Ensure Terraform is in the PATH (cron gives us /usr/bin:/bin)

source ~/.config/apprise/.env

# Navigate to the Terraform directory, relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/terraform" || exit 1

# A1.Flex capacity frees up in bursts, and it is per availability domain, so a
# run sweeps every AD before giving up. ad_index wraps modulo the AD count, so in
# a single-AD region like eu-paris-1 anything above 1 just replays the same failed
# apply — raise AD_COUNT only in a multi-AD region. Cron re-runs this until one
# apply lands; raise ATTEMPTS to loop standalone instead.
AD_COUNT="${AD_COUNT:-1}"
ATTEMPTS="${ATTEMPTS:-1}"
SLEEP_SECONDS="${SLEEP_SECONDS:-60}"

notify() { apprise -t "$1" -b "$2" "$APPRISE_TELEGRAM_URL"; }

# Applying with a different ad_index would force-replace a live instance.
if terraform state list 2>/dev/null | grep -q '^oci_core_instance\.'; then
  echo "Instance already provisioned, nothing to do"
  exit 0
fi

# Run Terraform commands
# terraform init
error_output="no apply attempted"
for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
  for ((ad = 0; ad < AD_COUNT; ad++)); do
    if error_output=$(terraform apply -auto-approve -var "ad_index=$ad" 2>&1 >/dev/null); then
      # Ship the ssh_config stanza with the success ping: capacity lands at
      # unpredictable hours, so the notification should be enough to get in
      # without coming back to a terminal to look the IP up.
      notify "Terraform Deployment Successful" "$(
        printf 'Instance up at %s (%s)\n\n%s' \
          "$(terraform output -raw public_ip)" \
          "$(terraform output -raw availability_domain)" \
          "$(terraform output -raw ssh_config)"
      )"
      exit 0
    fi
    # Only capacity is worth retrying elsewhere. Auth, config and state-lock
    # errors fail identically in every AD, so bail out instead of grinding.
    grep -q "Out of host capacity" <<<"$error_output" || break 2
  done
  if ((attempt < ATTEMPTS)); then
    sleep "$SLEEP_SECONDS"
  fi
done

# Send a failure message via Telegram using Apprise
echo "Deployment failed"
exit 1

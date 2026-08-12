variable "region" {
  description = "OCI region. Always Free compute only provisions in the tenancy home region."
  type        = string
  default     = "eu-paris-1"
}

variable "compartment_id" {
  description = "Compartment (here: tenancy) OCID."
  type        = string
  default     = "ocid1.tenancy.oc1..aaaaaaaam52t5hkkkaeuuqpcoign7frjt225effd7gsbp7zpxnggm4aqr7vq"
}

variable "subnet_id" {
  description = "Subnet OCID. Region-specific: must be replaced if var.region changes."
  type        = string
  default     = "ocid1.subnet.oc1.eu-paris-1.aaaaaaaapskf4lw5xbsv3o5pjjh7kq2dodfn6amksngx7ip63uynvwmahleq"
}

variable "image_id" {
  description = "Boot image OCID. Region-specific: must be replaced if var.region changes. Must be an aarch64 image, since A1.Flex is Ampere ARM. Changing this is ForceNew: it destroys the instance and re-enters the capacity lottery."
  type        = string
  # Canonical-Ubuntu-24.04-aarch64-2026.07.17-0. Ubuntu's OCI images growpart the
  # root filesystem to the whole boot volume on first boot; the Oracle Linux
  # images do not, and strand everything past 30 GB until oci-growfs is run.
  default = "ocid1.image.oc1.eu-paris-1.aaaaaaaaqb3hjmnty4rvidngmb2m4pqtmnrqingxqxqhutffjogbxw6hzcga"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into the instance. Read at plan time, so this file must exist on whichever host runs deploy.sh."
  type        = string
  default     = "~/.ssh/oracle.pub"
}

variable "ssh_host_alias" {
  description = "Host alias in the generated ~/.ssh/config stanza. Deliberately separate from var.instance_name, which names the resource in OCI."
  type        = string
  default     = "oracle"
}

variable "ssh_user" {
  description = "Default login user baked into the image. 'ubuntu' for Canonical images, 'opc' for Oracle Linux — must be changed alongside var.image_id."
  type        = string
  default     = "ubuntu"
}

variable "instance_name" {
  description = "Instance display name."
  type        = string
  default     = "mazzo"
}

variable "ad_index" {
  description = "Which availability domain to try, by index. Wraps modulo the AD count, so deploy.sh can sweep 0..N in regions with a single AD."
  type        = number
  default     = 0
}

# Always Free ceiling as of 2026: 1,500 OCPU-h + 9,000 GB-h/month on A1.Flex,
# which is 2 OCPU / 12 GB running 24/7. Oracle halved this from 4/24 with no
# warning, so treat these as values that may shrink again.
variable "ocpus" {
  description = "A1.Flex OCPUs. 2 is the Always Free 24/7 ceiling (1 OCPU = 1 physical Ampere core)."
  type        = number
  default     = 2
}

variable "memory_in_gbs" {
  description = "A1.Flex memory. 12 GB is the Always Free 24/7 ceiling."
  type        = number
  default     = 12
}

# Always Free block storage is one 200 GB pool shared by boot AND block volumes
# (limit `total-free-storage-gb`, AD-scoped), and it is spent entirely here.
# Splitting it into a separate data volume was considered and rejected: Balanced
# volumes deliver 60 IOPS/GB, so a 50 GB root would drop from 12,000 to 3,000
# IOPS, and OCI volumes can only grow, never shrink — the split is one-way.
variable "boot_volume_size_in_gbs" {
  description = "Boot volume size. 200 GB is the whole Always Free block storage pool, spent here rather than on the x86 micros."
  type        = number
  default     = 200
}

variable "budget_amount" {
  description = "Monthly budget in the tenancy's rate card currency. The Budgets API only accepts whole numbers, so 1 is the floor."
  type        = number
  default     = 1
}

# No default on purpose: this is a personal email and variables.tf is tracked.
# Set it in terraform/terraform.tfvars (gitignored, auto-loaded so cron still works)
# or export TF_VAR_budget_alert_recipient.
variable "budget_alert_recipient" {
  description = "Email for budget alerts. OCI budget alerts are email-only, so this cannot reuse the Apprise/Telegram path deploy.sh uses."
  type        = string
}

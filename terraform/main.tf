provider "oci" {
  config_file_profile = "DEFAULT" # Replace with your profile name if it's not "DEFAULT"
  region              = var.region
}
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 4.0.0" # Adjust the version as needed
    }
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

locals {
  # Sweeping ADs is the recommended way around "Out of host capacity". The
  # modulo keeps a caller looping ad_index=0,1,2 harmless in single-AD regions
  # (eu-paris-1 and eu-marseille-1 both have one).
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[
    var.ad_index % length(data.oci_identity_availability_domains.ads.availability_domains)
  ].name
}

# The provider plans a bogus in-place update when source_details.source_id
# changes, then fails at apply with "400-InvalidParameter, sourceDetails.kmsKeyId
# size must be between 1 and 255" — OCI cannot reimage a live instance.
# oracle/terraform-provider-oci#2133, still open. Keying a terraform_data on the
# image forces an honest replacement so the plan shows the capacity risk instead
# of hiding it behind a no-op update.
resource "terraform_data" "image_id" {
  input = var.image_id
}

resource "oci_core_instance" "generated_oci_core_instance" {
  lifecycle {
    replace_triggered_by = [terraform_data.image_id]

    # metadata is ForceNew, so adding user_data to the live instance plans as a
    # destroy. Scoped to the one key: creates still read it, and a changed
    # ssh_authorized_keys must still surface as the replacement it is.
    ignore_changes = [metadata["user_data"]]
  }

  agent_config {
    is_management_disabled = "false"
    is_monitoring_disabled = "false"
    plugins_config {
      desired_state = "DISABLED"
      name          = "WebLogic Management Service"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Java Management Service"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Hub Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }
  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }
  availability_domain = local.availability_domain
  compartment_id      = var.compartment_id
  create_vnic_details {
    assign_ipv6ip             = "false"
    assign_private_dns_record = "true"
    assign_public_ip          = "true"
    # Empty rather than omitted: nsg_ids is Optional+Computed, so leaving it out
    # means "keep whatever is attached" and strands any NSG bound to the VNIC.
    nsg_ids   = []
    subnet_id = var.subnet_id
  }
  display_name = var.instance_name
  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "true"
  metadata = {
    # chomp: file() keeps the trailing newline, which would show as a perpetual diff.
    "ssh_authorized_keys" = chomp(file(pathexpand(var.ssh_public_key_path)))
    "user_data"           = base64encode(file("${path.module}/cloud-init.yaml"))
  }
  shape = "VM.Standard.A1.Flex"
  shape_config {
    memory_in_gbs = var.memory_in_gbs
    ocpus         = var.ocpus
  }
  source_details {
    source_id               = var.image_id
    source_type             = "image"
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }
}

output "public_ip" {
  description = "Public IP of the instance."
  value       = oci_core_instance.generated_oci_core_instance.public_ip
}

output "availability_domain" {
  description = "Availability domain the instance actually landed in."
  value       = oci_core_instance.generated_oci_core_instance.availability_domain
}

# Rendered here rather than in deploy.sh so the IP, login user and key path stay
# next to the resources that define them. The public IP is only known after a
# successful apply, which is exactly when deploy.sh notifies.
output "ssh_config" {
  description = "Ready-to-paste ~/.ssh/config stanza for the instance."
  value       = <<-EOT
    Host ${var.ssh_host_alias}
        HostName ${oci_core_instance.generated_oci_core_instance.public_ip}
        User ${var.ssh_user}
        IdentityFile ${trimsuffix(var.ssh_public_key_path, ".pub")}
        IdentitiesOnly yes
  EOT
}

# The namespace is a tenancy-wide constant with no obvious home in the console,
# and every rclone/CLI call against the bucket needs it.
output "drive_bucket" {
  description = "Namespace and name of the drive bucket, as rclone needs them."
  value = {
    namespace = data.oci_objectstorage_namespace.this.namespace
    name      = oci_objectstorage_bucket.drive.name
  }
}

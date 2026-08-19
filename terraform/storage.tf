data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "drive" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.drive_bucket_name

  access_type = "NoPublicAccess"

  # ForceNew, and Always Free only covers 20 GB of Standard (plus 10 GB Archive).
  storage_tier = "Standard"

  # The realistic failure mode here is `rclone sync` run in the wrong direction.
  # Versioning is the only undo; it does bill deleted versions against the same
  # 20 GB, so prune with a lifecycle rule if the bucket ever fills up.
  versioning = "Enabled"
}

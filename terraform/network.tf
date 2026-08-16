# Imported, not created:
#   terraform import oci_core_security_list.default <ocid>
#
# Rules are a whole-set declaration, not a patch — dropping the port 22 block
# locks SSH out. Plan-check before applying.
#
# The host's own iptables must agree; see cloud-init.yaml.

data "oci_core_subnet" "instance" {
  subnet_id = var.subnet_id
}

resource "oci_core_security_list" "default" {
  compartment_id = var.compartment_id
  vcn_id         = data.oci_core_subnet.instance.vcn_id
  display_name   = "Default Security List for vcn-20240706-2304"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      type = 3
    }
  }

  # 80 is required even for a TLS-only site: Let's Encrypt answers the HTTP-01
  # challenge on it, at issuance and at every renewal.
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "HTTP from anywhere; also the Let's Encrypt HTTP-01 challenge"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "HTTPS from anywhere"
    tcp_options {
      min = 443
      max = 443
    }
  }
}

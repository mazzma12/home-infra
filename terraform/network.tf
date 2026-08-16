# Opening a port on OCI takes two layers, and both must agree: the VCN firewall
# (this file) and the host's own iptables (see cloud-init.yaml). Neither one on
# its own gets a packet to a listener on :80 or :443.
#
# 80 is not optional even for a TLS-only site: Let's Encrypt's HTTP-01 challenge
# is answered on 80 from outside, so blocking it blocks certificate issuance and
# every later renewal.
#
# This is the subnet's Default Security List, created by the console in 2024 and
# imported rather than created:
#
#   terraform import oci_core_security_list.default <security list OCID>
#
# Its rules are a whole-set declaration, not a patch — the four blocks below the
# new ones are the pre-existing rules, transcribed verbatim from the live list.
# Deleting or mistyping the port 22 block locks SSH out of the instance, so any
# change here must be plan-checked before apply.

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

  # --- pre-existing, do not remove -----------------------------------------

  ingress_security_rules {
    protocol    = "6" # TCP; OCI takes IANA protocol numbers, not names
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Fragmentation-needed, so path MTU discovery works from anywhere.
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

  # All destination-unreachable codes, but only from inside the VCN.
  ingress_security_rules {
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      type = 3
    }
  }

  # --- added for web traffic -------------------------------------------------

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

output "key_pair_name" {
  value       = module.key_pair.key_pair_name
  description = "Name of the created key pair."
}

output "key_pair_fingerprint" {
  value       = module.key_pair.key_pair_fingerprint
  description = "Fingerprint of the created key pair."
}

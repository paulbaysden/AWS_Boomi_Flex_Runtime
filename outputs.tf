output "namespace" {
  value = local.ns
}

output "claim_name" {
  value = local.pvc_name
}

output "efs_file_system_id" {
  value = aws_efs_file_system.flex.id
}

output "efs_access_point_id" {
  value = aws_efs_access_point.flex.id
}

output "ingress_service" {
  description = "Route your load balancer or gateway to this Service."
  value       = "ingress-gateway.${local.ns}.svc.cluster.local"
}

output "ingress_port" {
  description = "8443 for end-to-end TLS, 8080 when TLS terminates before the runtime."
  value       = local.tls_mode == "end_to_end" ? 8443 : 8080
}

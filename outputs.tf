output "EKS_CLUSTER_NAME" {
  description = "Name of the EKS Cluster"
  value = aws_eks_cluster.eks_cluster.name
}

output "oidc" {
  description = "OIDC(OpenID Connect) provider URL"
  value = trimprefix("${aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer}", "https://")
}
output "thumb" {
  description = "OIDC Provider용 CA-thumbprint"
  value = data.tls_certificate.cluster-tls.certificates.0.sha1_fingerprint
}

output "kubeconfig" {
  description = "EKS Cluster 접속을 위한 kubeconfig"
  value = local.kubeconfig
}
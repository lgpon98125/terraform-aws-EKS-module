# 1. EKS Cluster
  # 1-1. eks role 생성
  # 1-2. eks role과 policy 연동
  # 1-3. EKS Cluster 생성


# 1-1. EKS 클러스터에 접근하기 위한 Role 생성
resource "aws_iam_role" "role_eks" {
  name = "iam-${var.env}-${var.pjt}-role-eks"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = {
    Name    = "iam-${var.env}-${var.pjt}-role-eks",
    Service = "role-eks"
  }
}

# 1-2. EKS 클러스터를 위한 Role과 정책 연결
resource "aws_iam_role_policy_attachment" "att_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.role_eks.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.role_eks.name
}

# 1-3. EKS Cluster 생성
resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks-${var.env}-${var.pjt}-cluster"
  role_arn = aws_iam_role.role_eks.arn

  vpc_config { // eks에 private access 로 제한해야함
    endpoint_private_access = true
    endpoint_public_access  = true

    security_group_ids = [var.cluster_sg_id]
    subnet_ids         = [var.subnet-pria-id, var.subnet-pric-id, var.subnet-pria-pod-id, var.subnet-pric-pod-id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.att_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.att_AmazonEKSServicePolicy,
  ]

  tags = {
    Name    = "eks-${var.env}-${var.pjt}-cluster",
    Service = "cluster"
  }
}

data "aws_caller_identity" "current" {}

# OIDC Provider용 CA-thumbprint data 생성
data "tls_certificate" "cluster-tls" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}
# OIDC Provider 생성
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = [
    "sts.amazonaws.com",
  ]
  thumbprint_list = ["${data.tls_certificate.cluster-tls.certificates.0.sha1_fingerprint}"]
}


# 2. eks worker node group
  # 2-1. worker node를 위한 role 생성
  # 2-2. role과 EKSWorkerNode/EKS_CNI/EC2ContainerRegistryReadOnly/S3FullAccess policy 연동
  # 2-3. worker node group 생성
  # - subnet 설정
  # - instance type, disk size 설정
  # - auto scailing 설정 : desired/max/min size


# 2-1. worker node를 위한 role 생성
resource "aws_iam_role" "role_node" {
  name = "iam-${var.env}-${var.pjt}-role-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = {
    Name    = "iam-${var.env}-${var.pjt}-role-node",
    Service = "role-node"
  }
}

# 2-2. worker node를 위한 role과 정책 연결
resource "aws_iam_role_policy_attachment" "att_AmazonEKSWorkerNodePolicy" { // AWS EKS Worker Node Policy
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.role_node.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonEKS_CNI_Policy" { // AWS CNI가 VPC CIDR을 가지고 IP 할당하기에 필요 
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.role_node.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonEC2ContainerRegistryReadOnly" { // EC2 Container Registry에 대한 읽기전용 권한 부여
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.role_node.name
}

resource "aws_iam_role_policy_attachment" "att_AmazonS3FullAccess" { // S3 Access 권한 부여
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.role_node.name
}

# 2-3. eks worker node group 생성
resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.eks_cluster.name // eks-cluster name
  node_group_name = "eks-${var.env}-${var.pjt}-node"
  node_role_arn   = aws_iam_role.role_node.arn
  subnet_ids      = [var.subnet-pria-id, var.subnet-pric-id]
  instance_types  = var.node_instance_types
  disk_size       = var.node_disk_size
 
  scaling_config {
    desired_size = var.scailing_desired
    max_size     = var.scailing_max
    min_size     = var.scailing_min
  }

  depends_on = [
    aws_iam_role_policy_attachment.att_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.att_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.att_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.att_AmazonS3FullAccess,    
    null_resource.eks-secondary-cidr-1
  ]

    tags = {
    Name    = "eks-${var.env}-${var.pjt}-node",
    Service = "node"
  }
}

# 3. Load Balancer controller 배포
# - 아래 가이드 참고
# - https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/aws-load-balancer-controller.html

# EKS Cluster 정보 확인
data "aws_eks_cluster" "eks_cluster" {
  name = aws_eks_cluster.eks_cluster.name  
}
data "aws_eks_cluster_auth" "eks_cluster" {
  name = aws_eks_cluster.eks_cluster.name
}
# kubernetes Provider 사용, token을 발급받아 Cluster 접속
provider "kubernetes" {
  alias = "eks"
  host                   = data.aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", "${aws_eks_cluster.eks_cluster.name}"]
    command     = "aws"
  }
}

# local에서 kubeconfig, OIDC issuer URL 생성
locals {
  kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.eks_cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.eks_cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${aws_eks_cluster.eks_cluster.name}"
KUBECONFIG

CustomResourceDefinition = <<DEFINITION
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: eniconfigs.crd.k8s.amazonaws.com
spec:
  scope: Cluster
  group: crd.k8s.amazonaws.com
  version: v1alpha1
  names:
    plural: eniconfigs
    singular: eniconfig
    kind: ENIConfig
DEFINITION

ENIconfig = <<ENICONFIG
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2a
spec:
  subnet: ${var.subnet-pria-pod-id}
  securityGroups: 
    - ${var.cluster_sg_id}
---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ap-northeast-2c
spec:
  subnet: ${var.subnet-pric-pod-id}
  securityGroups: 
    - ${var.cluster_sg_id}
ENICONFIG

ServiceAccount = <<SERVICEACCOUNT
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller-${var.env}-${var.pjt}
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${aws_iam_role.aws-load-balancer-controller-role.arn}
SERVICEACCOUNT

  oidc = trimprefix("${aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer}", "https://")

}

# Load Balancer controller 동작에 필요한 IAM Policy 생성
resource "aws_iam_policy" "load-balancer-policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.env}-${var.pjt}"
  path        = "/"
  description = "AWS LoadBalancer Controller IAM Policy"

  policy = file("${path.module}/iam-policy.json")
}

# Load Balancer controller 동작에 필요한 IAM Role 생성
resource "aws_iam_role" "aws-load-balancer-controller-role" {
  name = "AmazonEKSLoadBalancerControllerRole-${var.env}-${var.pjt}"
  assume_role_policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.oidc}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller-${var.env}-${var.pjt}"
        }
      }
    }
  ]
})
}

# Load Balancer controller 동작에 필요한 IAM Policy-Role Attachment
resource "aws_iam_role_policy_attachment" "alb-controller-attachment" {
  role       = aws_iam_role.aws-load-balancer-controller-role.name
  policy_arn = aws_iam_policy.load-balancer-policy.arn
}

# EKS Pod의 Secondary CIDR 구성& Load Balancer controller 동작에 필요한 ServiceAccount 생성
resource "null_resource" "eks-secondary-cidr-1" {
  depends_on = [
    aws_eks_cluster.eks_cluster, 
    aws_iam_role_policy_attachment.alb-controller-attachment
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOF
mkdir -p ~/.kube
cat <<EOT > ~/.kube/config
${local.kubeconfig}
EOT
ls -al ./
ls -al ${path.module}
chmod +x ${path.module}/kubectl
chmod +x ${path.module}/aws-iam-authenticator
cd ${path.module}
export PATH=$PATH:$(pwd)
kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
sleep 20
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone
cat <<EOT > CustomResourceDefinition.yaml
${local.CustomResourceDefinition}
EOT
kubectl apply -f CustomResourceDefinition.yaml
ls -al ./
cat <<EOT > ENIconfig.yaml
${local.ENIconfig}
EOT
kubectl apply -f ENIconfig.yaml
kubectl get all --all-namespaces
echo "ENIconfig apply completed !"
kubectl get pod -o wide -A

cat <<EOT > ServiceAccount.yaml
${local.ServiceAccount}
EOT
kubectl apply -f ServiceAccount.yaml

    EOF
  }
}

# helm chart를 사용하여 aws-load-balancer-contoller 배포
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", "${aws_eks_cluster.eks_cluster.name}"]
      command     = "aws"
    }
  }
}

resource "helm_release" "aws-load-balancer-contoller" {
  name       = "${var.env}-${var.pjt}"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  set {
    name  = "clusterName"
    value = aws_eks_cluster.eks_cluster.name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller-${var.env}-${var.pjt}"
  }
  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/amazon/aws-load-balancer-controller"
  }
  depends_on = [ 
    aws_eks_node_group.node
  ]
}

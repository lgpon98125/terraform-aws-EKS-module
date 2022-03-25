# 1. EKS Cluster
  # 1-1. eks role 생성
  # 1-2. eks role과 policy 연동
  # 1-3. EKS Cluster 생성
  # - subnet은 sbn_pri 사용
  # - security group은 sg_cluster 사용
  # - public access는 제한


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

  vpc_config { // eks에 private access 로 제한함
    endpoint_private_access = true
    endpoint_public_access  = true

    security_group_ids = [var.sg_cluster_id]
    subnet_ids         = [var.subnet-pria-id, var.subnet-pric-id]
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
  ]

    tags = {
    Name    = "eks-${var.env}-${var.pjt}-node",
    Service = "node"
  }
}

# 3. ingress-controller 배포
# - 아래 AWS ingress-controller 가이드 참고
# - https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-alb-ingress-controller-setup/

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
# local에서 kubeconfig, ingress-contoller yaml, OIDC issuer URL 생성
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

  ingress-controller = <<CONTROLLER
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.4.0
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: targetgroupbindings.elbv2.k8s.aws
spec:
  additionalPrinterColumns:
    - JSONPath: .spec.serviceRef.name
      description: The Kubernetes Service's name
      name: SERVICE-NAME
      type: string
    - JSONPath: .spec.serviceRef.port
      description: The Kubernetes Service's port
      name: SERVICE-PORT
      type: string
    - JSONPath: .spec.targetType
      description: The AWS TargetGroup's TargetType
      name: TARGET-TYPE
      type: string
    - JSONPath: .spec.targetGroupARN
      description: The AWS TargetGroup's Amazon Resource Name
      name: ARN
      priority: 1
      type: string
    - JSONPath: .metadata.creationTimestamp
      name: AGE
      type: date
  group: elbv2.k8s.aws
  names:
    categories:
      - all
    kind: TargetGroupBinding
    listKind: TargetGroupBindingList
    plural: targetgroupbindings
    singular: targetgroupbinding
  scope: Namespaced
  subresources:
    status: {}
  validation:
    openAPIV3Schema:
      description: TargetGroupBinding is the Schema for the TargetGroupBinding API
      properties:
        apiVersion:
          description: 'APIVersion defines the versioned schema of this representation
            of an object. Servers should convert recognized schemas to the latest
            internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
          type: string
        kind:
          description: 'Kind is a string value representing the REST resource this
            object represents. Servers may infer this from the endpoint the client
            submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
          type: string
        metadata:
          type: object
        spec:
          description: TargetGroupBindingSpec defines the desired state of TargetGroupBinding
          properties:
            networking:
              description: networking provides the networking setup for ELBV2 LoadBalancer
                to access targets in TargetGroup.
              properties:
                ingress:
                  description: List of ingress rules to allow ELBV2 LoadBalancer to
                    access targets in TargetGroup.
                  items:
                    properties:
                      from:
                        description: List of peers which should be able to access
                          the targets in TargetGroup. At least one NetworkingPeer
                          should be specified.
                        items:
                          description: NetworkingPeer defines the source/destination
                            peer for networking rules.
                          properties:
                            ipBlock:
                              description: IPBlock defines an IPBlock peer. If specified,
                                none of the other fields can be set.
                              properties:
                                cidr:
                                  description: CIDR is the network CIDR. Both IPV4
                                    or IPV6 CIDR are accepted.
                                  type: string
                              required:
                                - cidr
                              type: object
                            securityGroup:
                              description: SecurityGroup defines a SecurityGroup peer.
                                If specified, none of the other fields can be set.
                              properties:
                                groupID:
                                  description: GroupID is the EC2 SecurityGroupID.
                                  type: string
                              required:
                                - groupID
                              type: object
                          type: object
                        type: array
                      ports:
                        description: List of ports which should be made accessible
                          on the targets in TargetGroup. If ports is empty or unspecified,
                          it defaults to all ports with TCP.
                        items:
                          properties:
                            port:
                              anyOf:
                                - type: integer
                                - type: string
                              description: The port which traffic must match. When
                                NodePort endpoints(instance TargetType) is used, this
                                must be a numerical port. When Port endpoints(ip TargetType)
                                is used, this can be either numerical or named port
                                on pods. if port is unspecified, it defaults to all
                                ports.
                              x-kubernetes-int-or-string: true
                            protocol:
                              description: The protocol which traffic must match.
                                If protocol is unspecified, it defaults to TCP.
                              enum:
                                - TCP
                                - UDP
                              type: string
                          type: object
                        type: array
                    required:
                      - from
                      - ports
                    type: object
                  type: array
              type: object
            serviceRef:
              description: serviceRef is a reference to a Kubernetes Service and ServicePort.
              properties:
                name:
                  description: Name is the name of the Service.
                  type: string
                port:
                  anyOf:
                    - type: integer
                    - type: string
                  description: Port is the port of the ServicePort.
                  x-kubernetes-int-or-string: true
              required:
                - name
                - port
              type: object
            targetGroupARN:
              description: targetGroupARN is the Amazon Resource Name (ARN) for the
                TargetGroup.
              type: string
            targetType:
              description: targetType is the TargetType of TargetGroup. If unspecified,
                it will be automatically inferred.
              enum:
                - instance
                - ip
              type: string
          required:
            - serviceRef
            - targetGroupARN
          type: object
        status:
          description: TargetGroupBindingStatus defines the observed state of TargetGroupBinding
          properties:
            observedGeneration:
              description: The generation observed by the TargetGroupBinding controller.
              format: int64
              type: integer
          type: object
      type: object
  version: v1alpha1
  versions:
    - name: v1alpha1
      served: true
      storage: false
    - name: v1beta1
      served: true
      storage: true
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingWebhookConfiguration
metadata:
  annotations:
    cert-manager.io/inject-ca-from: kube-system/aws-load-balancer-serving-cert
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-webhook
webhooks:
  - clientConfig:
      caBundle: Cg==
      service:
        name: aws-load-balancer-webhook-service
        namespace: kube-system
        path: /mutate-v1-pod
    failurePolicy: Fail
    name: mpod.elbv2.k8s.aws
    namespaceSelector:
      matchExpressions:
        - key: elbv2.k8s.aws/pod-readiness-gate-inject
          operator: In
          values:
            - enabled
    rules:
      - apiGroups:
          - ""
        apiVersions:
          - v1
        operations:
          - CREATE
        resources:
          - pods
    sideEffects: None
  - clientConfig:
      caBundle: Cg==
      service:
        name: aws-load-balancer-webhook-service
        namespace: kube-system
        path: /mutate-elbv2-k8s-aws-v1beta1-targetgroupbinding
    failurePolicy: Fail
    name: mtargetgroupbinding.elbv2.k8s.aws
    rules:
      - apiGroups:
          - elbv2.k8s.aws
        apiVersions:
          - v1beta1
        operations:
          - CREATE
          - UPDATE
        resources:
          - targetgroupbindings
    sideEffects: None
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-controller-${var.env}-${var.pjt}
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-controller-leader-election-role
  namespace: kube-system
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
    verbs:
      - create
  - apiGroups:
      - ""
    resourceNames:
      - aws-load-balancer-controller-leader
    resources:
      - configmaps
    verbs:
      - get
      - update
      - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-controller-${var.env}-${var.pjt}-role
rules:
  - apiGroups:
      - ""
    resources:
      - endpoints
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - events
    verbs:
      - create
      - patch
  - apiGroups:
      - ""
    resources:
      - namespaces
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - pods/status
    verbs:
      - patch
      - update
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - services
    verbs:
      - get
      - list
      - patch
      - update
      - watch
  - apiGroups:
      - ""
    resources:
      - services/status
    verbs:
      - patch
      - update
  - apiGroups:
      - elbv2.k8s.aws
    resources:
      - targetgroupbindings
    verbs:
      - create
      - delete
      - get
      - list
      - patch
      - update
      - watch
  - apiGroups:
      - elbv2.k8s.aws
    resources:
      - targetgroupbindings/status
    verbs:
      - patch
      - update
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - patch
      - update
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses/status
    verbs:
      - patch
      - update
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingressclasses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - patch
      - update
      - watch
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses/status
    verbs:
      - patch
      - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-controller-leader-election-rolebinding
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: aws-load-balancer-controller-leader-election-role
subjects:
  - kind: ServiceAccount
    name: aws-load-balancer-controller-${var.env}-${var.pjt}
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-controller-${var.env}-${var.pjt}-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: aws-load-balancer-controller-${var.env}-${var.pjt}-role
subjects:
  - kind: ServiceAccount
    name: aws-load-balancer-controller-${var.env}-${var.pjt}
    namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-webhook-service
  namespace: kube-system
spec:
  ports:
    - port: 443
      targetPort: 9443
  selector:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-controller-${var.env}-${var.pjt}
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  template:
    metadata:
      labels:
        app.kubernetes.io/component: controller
        app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
    spec:
      containers:
        - args:
            - --cluster-name=${aws_eks_cluster.eks_cluster.name}
            - --ingress-class=alb
          image: amazon/aws-alb-ingress-controller:v2.1.0
          livenessProbe:
            failureThreshold: 2
            httpGet:
              path: /healthz
              port: 61779
              scheme: HTTP
            initialDelaySeconds: 30
            timeoutSeconds: 10
          name: controller
          ports:
            - containerPort: 9443
              name: webhook-server
              protocol: TCP
          resources:
            limits:
              cpu: 200m
              memory: 500Mi
            requests:
              cpu: 100m
              memory: 200Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
          volumeMounts:
            - mountPath: /tmp/k8s-webhook-server/serving-certs
              name: cert
              readOnly: true
      securityContext:
        fsGroup: 1337
      serviceAccountName: aws-load-balancer-controller-${var.env}-${var.pjt}
      terminationGracePeriodSeconds: 10
      volumes:
        - name: cert
          secret:
            defaultMode: 420
            secretName: aws-load-balancer-webhook-tls
---
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-serving-cert
  namespace: kube-system
spec:
  dnsNames:
    - aws-load-balancer-webhook-service.kube-system.svc
    - aws-load-balancer-webhook-service.kube-system.svc.cluster.local
  issuerRef:
    kind: Issuer
    name: aws-load-balancer-selfsigned-issuer
  secretName: aws-load-balancer-webhook-tls
---
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-selfsigned-issuer
  namespace: kube-system
spec:
  selfSigned: {}
---
apiVersion: admissionregistration.k8s.io/v1beta1
kind: ValidatingWebhookConfiguration
metadata:
  annotations:
    cert-manager.io/inject-ca-from: kube-system/aws-load-balancer-serving-cert
  creationTimestamp: null
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller-${var.env}-${var.pjt}
  name: aws-load-balancer-webhook
webhooks:
  - clientConfig:
      caBundle: Cg==
      service:
        name: aws-load-balancer-webhook-service
        namespace: kube-system
        path: /validate-elbv2-k8s-aws-v1beta1-targetgroupbinding
    failurePolicy: Fail
    name: vtargetgroupbinding.elbv2.k8s.aws
    rules:
      - apiGroups:
          - elbv2.k8s.aws
        apiVersions:
          - v1beta1
        operations:
          - CREATE
          - UPDATE
        resources:
          - targetgroupbindings
    sideEffects: None
CONTROLLER

  oidc = trimprefix("${aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer}", "https://")

}
# ingress-contoller 동작에 필요한 IAM Policy 생성
resource "aws_iam_policy" "load-balancer-policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.env}-${var.pjt}"
  path        = "/"
  description = "AWS LoadBalancer Controller IAM Policy"

  policy = file("${path.module}/iam-policy.json")
}

# ingress-contoller 동작에 필요한 IAM Role 생성
resource "aws_iam_role" "aws-load-balancer-controller-role" {
  name = "aws-load-balancer-controller-${var.env}-${var.pjt}"
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

# ingress-contoller 동작에 필요한 IAM Policy-Role Attachment
resource "aws_iam_role_policy_attachment" "alb-controller-attachment" {
  role       = "aws-load-balancer-controller-${var.env}-${var.pjt}"
  policy_arn = "${aws_iam_policy.load-balancer-policy.arn}"

  depends_on = [
    aws_iam_policy.load-balancer-policy, 
    aws_iam_role.aws-load-balancer-controller-role
  ]
}

# Null local-exec를 사용하여 위 local에서 생성한 kubeconfig, ingress-controller 정보로 yaml파일 생성,
# kubectl apply를 통해 cert-manager.yaml(템플릿에 파일 포함되어있음), ingress-contoller.yaml 배포
resource "null_resource" "kubectl" {
   depends_on = [
    aws_eks_node_group.node, 
    aws_iam_policy.load-balancer-policy, 
    aws_iam_role.aws-load-balancer-controller-role, 
    aws_iam_role_policy_attachment.alb-controller-attachment
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    # Load credentials to local environment so subsequent kubectl commands can be run
    working_dir = "${path.module}/"
    command = <<EOF
mkdir -p ~/.kube
cat <<EOT > ~/.kube/config
${local.kubeconfig}
EOT
ls -al ./
cat <<EOT > ingress-controller.yaml
${local.ingress-controller}
EOT
ls -al ./
chmod +x ./kubectl
chmod +x ./aws-iam-authenticator
export PATH=$PATH:$(pwd)
./kubectl version --client
./kubectl version
./kubectl apply -f cert-manager.yaml
./kubectl get all --all-namespaces
./kubectl rollout status deployment cert-manager-webhook -n cert-manager
./kubectl get all --all-namespaces
./kubectl apply -f ingress-controller.yaml
./kubectl rollout status deployment aws-load-balancer-controller-${var.env}-${var.pjt} -n kube-system
./kubectl get all --all-namespaces
    EOF
  }
}

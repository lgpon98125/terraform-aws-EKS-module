# EKS-Module
EKS Cluster, Node Group 생성 및 Ingress-controller 배포

![image](https://lucid.app/publicSegments/view/a6814dd0-9916-4021-8af6-210b08d0fde3/image.png)


# 파일 정의
### [variable.tf](https://github.com/cloudarchitectureteam/terraform-aws-EKS-Module/blob/main/variable.tf) 
  - Input variable 선언

### [main.tf](https://github.com/cloudarchitectureteam/terraform-aws-EKS-Module/blob/main/main.tf)
  - EKS Cluster용 Role 생성, Policy 연동, EKS Cluster 생성
  - EKS Worker Node용 Role 생성, Policy 연동, EKS Worker Node Group 생성
  - Ingress-controller 배포를 위한 Kubeconfig 생성, Ingress-controller yaml파일 생성, Role 생성, Policy 생성, Role-Policy 연동, local-exec를 사용해 cert-manager, Ingress-controller 배포
  - AWS ingress-controller 가이드 참고 
  (https://aws.amazon.com/ko/premiumsupport/knowledge-center/eks-alb-ingress-controller-setup/)

### [output.tf](https://github.com/cloudarchitectureteam/terraform-aws-EKS-Module/blob/main/output.tf)
  - Output 값 정의


# Required Inputs
| Name | Description | Type | Default |
|-------|--------------|------|---------|
| env | environment : dev / stg / prod | `string` | N/A |
| pjt | project name | `string` | N/A |
| sg_cluster_id | Description: (Required) List of security group IDs for the cross-account elastic network interfaces that Amazon EKS creates to use to allow communication between your worker nodes and the Kubernetes control plane. | `string` | N/A |
| subnet-pria-id | private subnet id in ap-northeast-2a zone | `string` | N/A |
| subnet-pric-id | private subnet id in ap-northeast-2c zone | `string` | N/A |

# Optional Inputs
| Name | Description | Type | Default |
|-------|--------------|------|---------|
| node_disk_size | disk size of EKS worker nodes | `string` | `100` |
| node_instance_types | instance type of EKS worker nodes | `list` | `[ "t3.small" ]` |
| scailing_desired | scailing config. Desired number of worker nodes | `string` | `2` |
| scailing_max | scailing config. Maximum number of worker nodes | `string` | `6` |
| scailing_min | scailing config. Minimum number of worker nodes | `string` | `2` |

# Outputs
| Name | Description |
|-------|------------------------------|
| EKS_CLUSTER_NAME | Name of the EKS Cluster |
| kubeconfig | EKS Cluster 접속을 위한 kubeconfig |
| oidc | OIDC(OpenID Connect) provider URL |
| thumb | OIDC Provider용 CA-thumbprint |
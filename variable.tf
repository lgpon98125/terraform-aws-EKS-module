#####################
# default tag
#####################
variable "env" {
  description = "(Required) environment : dev / stg / prod"
}

variable "pjt" {
  description = "(Required) project name"
}

#####################
# network
#####################

variable "subnet-pria-id" {
  description = "(Required) private subnet id for worker nodes in ap-northeast-2a zone"
}

variable "subnet-pric-id" {
  description = "(Required) private subnet id for worker nodes in ap-northeast-2c zone"
}

variable "subnet-pria-pod-id" {
  description = "(Required) private subnet id for pods in ap-northeast-2a zone"
}

variable "subnet-pric-pod-id" {
  description = "(Required) private subnet id for pods in ap-northeast-2c zone"
}

#####################
# eks-node
#####################
variable "node_instance_types" {
  description = "(Optional) instance type of EKS worker nodes"
  default = ["t3.small"]
}

variable "node_disk_size" {
  description = "(Optional) disk size of EKS worker nodes"
  default = 100
}

variable "scailing_desired" {
  description = "(Optional) scailing config. Desired number of worker nodes"
  default     = 2
}

variable "scailing_max" {
  description = "(Optional) scailing config. Maximum number of worker nodes"
  default     = 6
}

variable "scailing_min" {
  description = "(Optional) scailing config. Minimum number of worker nodes"
  default     = 2
}


variable "cluster_sg_id" {
  description = "(Required) List of security group IDs for the cross-account elastic network interfaces that Amazon EKS creates to use to allow communication between your worker nodes and the Kubernetes control plane."
}
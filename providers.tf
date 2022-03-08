terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "1.10.0"
    }
  }
  cloud {
    organization = "guts"

    workspaces {
      name = "guts-eks-dev"
    }
  }
}
provider "aws" {
  region = "us-east-2"
}

provider "kubernetes" {
  load_config_file   = false
  host               = data.aws_eks_cluster.eks-cluster.endpoint
  client_certificate = base64decode(data.aws_eks_cluster.eks-cluster.certificate_authority[0].data)
  token              = data.aws_eks_cluster_auth.eks-auth.token
  insecure           = true
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks-cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks-cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.eks-cluster.name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.eks-cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks-cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks-auth.token
  load_config_file       = false
}
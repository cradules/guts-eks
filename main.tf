
#Create VPC
module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = var.vpc-name
  cidr                 = var.vpc-cidr
  azs                  = var.vpc-azs
  public_subnets       = var.vpc-public-subnets
  enable_dns_hostnames = var.vpc-enable-dns-hostnames
  tags = {
    "Name"        = "eks-${var.eks-cluster-name}"
    "Environment" = var.environment
    "Terraform"   = "true"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.eks-cluster-name}" = "shared"
  }
}

#Create EKS Cluster with IRSA integration
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = var.eks-cluster-name
  cluster_version = var.eks-cluster-version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnets

  eks_managed_node_group_defaults = {
    # We are using the IRSA created below for permissions
    # This is a better practice as well so that the nodes do not have the permission,
    # only the VPC CNI addon will have the permission
    iam_role_attach_cni_policy = false
  }

  eks_managed_node_groups = {
    capacity_type = "SPOT"
    default       = {}
  }

  cluster_addons = {
    vpc-cni = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
    }
  }

  tags = {
    "Name"        = var.eks-cluster-name
    "Environment" = var.environment
    "Terraform"   = "true"
  }
}

# Create CNI IRSA integration

module "vpc_cni_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name             = "vpc-cni-role-${var.eks-cluster-name}"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
  tags = {
    "Name"        = "vpc-cni-irsa-${var.eks-cluster-name}"
    "Environment" = var.environment
    "Terraform"   = "true"
  }
}



# Add Karpenter IRSA

module "karpenter_irsa" {
  source                             = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name                          = "karpenter-controller-${var.eks-cluster-name}"
  attach_karpenter_controller_policy = true
  karpenter_controller_cluster_ids   = [module.eks.cluster_id]
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["default"].iam_role_arn

  ]
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
  tags = {
    "Name"        = "karpenter-irsa-${var.eks-cluster-name}"
    "Environment" = var.environment
    "Terraform"   = "true"
  }
}

## Install karpenter
#module "karpenter" {
#  source     = "terraform-module/release/helm"
#  namespace  = "karpenter"
#  repository = "https://charts.karpenter.sh/"
#  app = {
#    name          = "karpenter"
#    version       = "0.6.4"
#    chart         = "karpenter"
#    force_update  = true
#    wait          = false
#    recreate_pods = true
#    deploy        = 1
#  }
#  set = [
#    {
#      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#      value = module.karpenter_irsa.iam_role_arn
#    },
#    {
#      name  = "clusterName"
#      value = var.eks-cluster-name
#    },
#    {
#      name  = "clusterEndpoint"
#      value = module.eks.cluster_endpoint
#    }
#  ]
#}

resource "helm_release" "karpenter" {
  depends_on = [module.eks]
  repository = "https://charts.karpenter.sh/"
  chart = "karpenter"
  name  = "karpenter"
  namespace = "karpenter"
  create_namespace = true
  version = "0.6.4"
  set  {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.karpenter_irsa.iam_role_arn
    }

  set  {
      name  = "clusterName"
      value = var.eks-cluster-name
    }
  set {
      name  = "clusterEndpoint"
      value = module.eks.cluster_endpoint
    }
}

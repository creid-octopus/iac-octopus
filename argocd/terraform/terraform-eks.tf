# ── EKS Cluster ──────────────────────────────────────────────────────────────
# Tier 1 resource: provisions the AWS infrastructure (VPC, EKS cluster, node group)
# via the terraform-aws-modules/eks module.
#
# This is the only cloud-specific Tier 1 resource set. Run:
#   terraform apply -target=module.eks
# to provision just the cluster. Everything downstream (ArgoCD, gateway, agent)
# depends on the cluster endpoint being reachable, not on any specific file.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.34"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # VPC configuration — the module expects an existing VPC with subnets
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Node groups — single managed group, closest equivalent to AKS default_node_pool
  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    default = {
      node_group_name = "${local.cluster_name}-nodes"

      min_size     = var.node_min_count
      max_size     = var.node_max_count
      desired_size = var.node_min_count

      instance_types = [var.node_size]
      subnet_ids     = aws_subnet.private[*].id

      # IAM policies for worker nodes
      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy      = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEKS_CNI_Policy           = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  tags = {
    environment = var.environment
    project     = "argocd-demo"
    managed_by  = "terraform"
  }
}

# ── VPC (required pre-dependency for the EKS module) ──────────────────────────
# The EKS module accepts an existing VPC; we create a minimal VPC here.
# The module does NOT create a VPC by default — it assumes one exists.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    name               = "${local.cluster_name}-vpc"
    environment        = local.env
    cluster_name       = local.cluster_name
    project            = "argocd-demo"
    managed_by         = "terraform"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    name                                        = "${local.cluster_name}-private-${var.availability_zones[count.index]}"
    environment                                 = local.env
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.availability_zones))
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    name                                        = "${local.cluster_name}-public-${var.availability_zones[count.index]}"
    environment                                 = local.env
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    name        = "${local.cluster_name}-igw"
    environment = local.env
    managed_by  = "terraform"
  }
}

# Route public subnets to the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    name        = "${local.cluster_name}-public-rt"
    environment = local.env
    managed_by  = "terraform"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT gateway for private subnet outbound (needed for node container pulls)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    name        = "${local.cluster_name}-nat-eip"
    environment = local.env
    managed_by  = "terraform"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    name        = "${local.cluster_name}-nat"
    environment = local.env
    managed_by  = "terraform"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    name        = "${local.cluster_name}-private-rt"
    environment = local.env
    managed_by  = "terraform"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

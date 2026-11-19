// Minimal standalone EKS cluster (no external module) to avoid module input mismatches.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "eks-vpc-${var.cluster_name}"
  }
}

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "eks-public-${count.index}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "eks-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "eks-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  version = var.k8s_version

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
    endpoint_public_access = true
    public_access_cidrs = ["0.0.0.0/0"]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy]
}

resource "aws_iam_role" "node_group" {
  name = "eks-node-role-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_launch_template" "node_lt" {
  name_prefix   = "eks-nt-${var.cluster_name}-"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = var.node_instance_type

  lifecycle { create_before_destroy = true }
}

data "aws_ami" "eks_worker" {
  most_recent = true
  owners      = ["602401143452"] # Amazon EKS optimized AMI owner (may vary by region)
  filter {
    name   = "name"
    values = ["amazon-eks-node-*-*"]
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-${var.cluster_name}"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = var.node_desired_count
    max_size     = var.node_desired_count + 1
    min_size     = 1
  }

  capacity_type = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.node_lt.id
    version = "$Latest"
  }

  depends_on = [aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy]
}


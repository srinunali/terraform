provider "aws" {

  region = "ap-south-1"
}

resource "aws_vpc" "k8s_vpc" {

  cidr_block = "10.10.0.0/16"


  tags = {
    Name = "k8s-cluster-vpc"
  }

}

resource "aws_subnet" "k8s_sub" {

  count                   = 2
  cidr_block              = cidrsubnet(aws_vpc.k8s_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)
  vpc_id                  = aws_vpc.k8s_vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet"
  }

}



resource "aws_internet_gateway" "k8s_igw" {

  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }

}

resource "aws_route_table" "k8s_rt" {

  vpc_id = aws_vpc.k8s_vpc.id

  route {

    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s-rt"
  }

}

resource "aws_route_table_association" "k8s_sub_rt" {

  count          = length(aws_subnet.k8s_sub)
  subnet_id      = aws_subnet.k8s_sub[count.index].id
  route_table_id = aws_route_table.k8s_rt.id

}



resource "aws_security_group" "k8s_SG" {

  name   = "k8s-sg"
  vpc_id = aws_vpc.k8s_vpc.id

  egress {

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-sg"
  }

}

resource "aws_eks_cluster" "k8s_master" {

  name     = "k8s-cluster"
  role_arn = aws_iam_role.k8s_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.k8s_sub[*].id
    security_group_ids = [aws_security_group.k8s_SG.id]
  }

  depends_on = [aws_iam_role_policy_attachment.k8s_role_policy]

  tags = {
    Name = "k8s-master"
  }
}

resource "aws_eks_node_group" "k8s_node_group" {

  cluster_name    = aws_eks_cluster.k8s_master.name
  node_group_name = "k8s-node-group"
  node_role_arn   = aws_iam_role.k8s_node_role.arn
  subnet_ids      = aws_subnet.k8s_sub[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t2.large"]
  remote_access {
    ec2_ssh_key               = var.k8s-key
    source_security_group_ids = [aws_security_group.k8s_SG.id]
  }

  depends_on = [aws_eks_cluster.k8s_master]

  tags = {
    Name = "k8s-node-group"
  }

}

resource "aws_iam_role" "k8s_role" {

  name = "k8s-role"

  assume_role_policy = <<EOF
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
EOF

  tags = {
    Name = "k8s-role"
  }
}

resource "aws_iam_role_policy_attachment" "k8s_role_policy" {

  role       = aws_iam_role.k8s_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

}

resource "aws_iam_role" "k8s_node_role" {
  name = "k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })



  tags = {
    Name = "k8s-node-role"
  }
}


resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.k8s_node_role.name
}





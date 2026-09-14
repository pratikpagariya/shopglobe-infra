###############################################################################
# VPC Module — main.tf
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Flatten AZ/subnet pairs for easy iteration
  public_subnet_map = {
    for idx, cidr in var.public_subnet_cidrs :
    "${local.name_prefix}-public-${idx + 1}" => {
      cidr = cidr
      az   = var.availability_zones[idx % length(var.availability_zones)]
    }
  }

  private_subnet_map = {
    for idx, cidr in var.private_subnet_cidrs :
    "${local.name_prefix}-private-${idx + 1}" => {
      cidr = cidr
      az   = var.availability_zones[idx % length(var.availability_zones)]
    }
  }

  common_tags = merge(var.tags, {
    Module = "vpc"
  })
}

###############################################################################
# VPC
###############################################################################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

###############################################################################
# Internet Gateway
###############################################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

###############################################################################
# Public Subnets
###############################################################################
resource "aws_subnet" "public" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                     = each.key
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

###############################################################################
# Private Subnets
###############################################################################
resource "aws_subnet" "private" {
  for_each = local.private_subnet_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name                              = each.key
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

###############################################################################
# Elastic IPs for NAT Gateways
###############################################################################
resource "aws_eip" "nat" {
  # One EIP per AZ when multi-NAT, else one total
  for_each = var.single_nat_gateway ? { "nat" = var.availability_zones[0] } : {
    for az in var.availability_zones : az => az
  }

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eip-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# NAT Gateways — placed in first public subnet of each AZ
###############################################################################
locals {
  # Map AZ → first public subnet id in that AZ
  public_subnet_by_az = {
    for k, s in aws_subnet.public : s.availability_zone => s.id...
  }

  nat_gateway_map = var.single_nat_gateway ? {
    "nat" = {
      az        = var.availability_zones[0]
      subnet_id = local.public_subnet_by_az[var.availability_zones[0]][0]
      eip_id    = aws_eip.nat["nat"].id
    }
    } : {
    for az in var.availability_zones : az => {
      az        = az
      subnet_id = local.public_subnet_by_az[az][0]
      eip_id    = aws_eip.nat[az].id
    }
  }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateway_map

  allocation_id = each.value.eip_id
  subnet_id     = each.value.subnet_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Public Route Table
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-public"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Private Route Tables — one per NAT gateway
###############################################################################
resource "aws_route_table" "private" {
  for_each = aws_nat_gateway.this

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = each.value.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-private-${each.key}"
  })
}

# Associate each private subnet to the correct NAT route table
locals {
  private_subnet_rt_map = {
    for k, s in aws_subnet.private :
    k => var.single_nat_gateway ? aws_route_table.private["nat"].id : aws_route_table.private[s.availability_zone].id
  }
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnet_rt_map

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = each.value
}

###############################################################################
# Security Groups (generic, reusable)
###############################################################################
resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = "${local.name_prefix}-sg-${each.key}"
  description = each.value.description
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = each.value.ingress_rules
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", [])
      security_groups = lookup(ingress.value, "security_groups", [])
      self            = lookup(ingress.value, "self", false)
    }
  }

  dynamic "egress" {
    for_each = each.value.egress_rules
    content {
      description     = egress.value.description
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", [])
      security_groups = lookup(egress.value, "security_groups", [])
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg-${each.key}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

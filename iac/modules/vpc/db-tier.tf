# A third tier with NO default route at all. Not even NAT. The database can
# neither reach the internet nor be reached from it -- stronger than any
# security group, because there is no path for a packet to take.
locals {
  db_subnet_map = {
    for idx, cidr in var.db_subnet_cidrs :
    "${local.name_prefix}-db-${idx + 1}" => {
      cidr = cidr
      az   = var.availability_zones[idx % length(var.availability_zones)]
    }
  }
}

resource "aws_subnet" "db" {
  for_each = local.db_subnet_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name = each.key
    Tier = "database"
  })
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  # Deliberately no route block. Only the implicit local VPC route exists.
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-db"
  })
}

resource "aws_route_table_association" "db" {
  for_each = aws_subnet.db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.db.id
}

resource "aws_db_subnet_group" "this" {
  count = length(var.db_subnet_cidrs) > 0 ? 1 : 0

  name       = "${local.name_prefix}-db"
  subnet_ids = [for s in aws_subnet.db : s.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db"
  })
}

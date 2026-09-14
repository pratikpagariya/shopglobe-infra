# Gateway endpoints are FREE and work via route-table entries.
# Interface endpoints are ENIs (~$7/mo each) but kill the $0.045/GB NAT data
# processing charge. Every ECR pull, every Secrets Manager call, every log
# push from a private subnet currently goes out through NAT and is billed
# per gigabyte. This is the single biggest avoidable line in a private VPC.

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [aws_route_table.db.id],
  )

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-s3" })
}

resource "aws_security_group" "endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name        = "${local.name_prefix}-vpce"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "TLS from anywhere in the VPC"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce" })
}

# ecr.api = the control-plane calls (auth, describe).
# ecr.dkr = the actual layer pulls -- this is where the gigabytes are.
# You need BOTH; people add only one and wonder why NAT traffic barely moved.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? toset([
    "ecr.api", "ecr.dkr", "sts", "secretsmanager", "logs",
    "elasticloadbalancing", "autoscaling", "ec2",
  ]) : toset([])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true # without this, the AWS SDK still resolves to the public endpoint

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-${each.key}" })
}

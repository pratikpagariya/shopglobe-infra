# Per-ENI connection records with an ACCEPT/REJECT verdict. The definitive
# answer to "did the packet even arrive?" -- which is the question you cannot
# answer from inside the instance.
resource "aws_cloudwatch_log_group" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${local.name_prefix}"
  retention_in_days = var.flow_log_retention_days # NEVER leave unset: unset = forever = billed forever
  tags              = local.common_tags
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  count              = var.enable_flow_logs ? 1 : 0
  name               = "${local.name_prefix}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "flow" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "write-flow-logs"
  role  = aws_iam_role.flow[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream", "logs:PutLogEvents",
        "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.flow[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id       = aws_vpc.this.id
  traffic_type = "REJECT" # REJECT only: ALL is 10x the volume and cost, and
  # rejects are what you actually investigate
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn         = aws_iam_role.flow[0].arn

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-flow" })
}

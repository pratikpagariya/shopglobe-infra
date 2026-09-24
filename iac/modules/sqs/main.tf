locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "sqs" })
}

# DLQ first -- the main queue's redrive policy references it.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-${var.queue_name}-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true
  tags                      = merge(local.common_tags, { Name = "${local.name_prefix}-${var.queue_name}-dlq" })
}

resource "aws_sqs_queue" "this" {
  name = "${local.name_prefix}-${var.queue_name}"

  # THE ONE THAT BITES. Shorter than your processing time and SQS hands the
  # same message to another consumer while you are still working on it -- so
  # you process it twice, forever. Rule of thumb: ~6x your p99 processing time.
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # Long polling: one API call parked for 20s instead of 20 empty polls a
  # second. Cheaper AND lower latency.
  receive_wait_time_seconds = 20

  message_retention_seconds = var.retention_seconds
  sqs_managed_sse_enabled   = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    # After N failed receives the message moves to the DLQ, so one poison
    # message cannot block the queue behind it.
    maxReceiveCount = var.max_receive_count
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${var.queue_name}" })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

# Alert input for day 5. Age of the oldest message is the right signal for a
# queue -- depth alone cannot distinguish "busy" from "stuck".
resource "aws_cloudwatch_metric_alarm" "oldest_message" {
  count               = var.alarm_oldest_message_seconds > 0 ? 1 : 0
  alarm_name          = "${local.name_prefix}-${var.queue_name}-backlog"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.alarm_oldest_message_seconds
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { QueueName = aws_sqs_queue.this.name }
  tags                = local.common_tags
}

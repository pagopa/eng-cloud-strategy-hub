output "sqs_queue_arn" {
  value = aws_sqs_queue.queue.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.queue.url
}

output "sqs_deadletter_queue_arn" {
  value = aws_sqs_queue.deadletter_queue.arn
}

output "sqs_deadletter_queue_url" {
  value = aws_sqs_queue.deadletter_queue.url
}

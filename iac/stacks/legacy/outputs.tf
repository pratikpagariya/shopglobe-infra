output "app_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "prom_url" {
  value = "http://${aws_instance.mon.public_ip}:9090"
}

output "grafana_url" {
  value = "http://${aws_instance.mon.public_ip}:3000"
}

output "db_endpoint" {
  value = aws_db_instance.pg.address
}

output "mon_instance_id" {
  value = aws_instance.mon.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

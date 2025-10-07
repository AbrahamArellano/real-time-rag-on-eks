output "indexing_complete" {
  description = "Flag indicating indexing is complete"
  value       = null_resource.index_logs.id != "" ? true : false
}

output "logs_generated" {
  description = "Timestamp of logs generation"
  value       = null_resource.generate_logs.id
}

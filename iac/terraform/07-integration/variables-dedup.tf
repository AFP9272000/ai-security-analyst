# Added in the alert-dedup fix (ADR-0019). Separate file so it merges
# cleanly with the existing variables.tf (Terraform reads all *.tf).

variable "dedup_ttl_hours" {
  description = <<-EOT
    Suppress repeat alerts for the same finding id for this many hours.
    Security Hub and GuardDuty re-import the same finding repeatedly; this
    is the window during which only the first alert is sent. Raise it
    (e.g. 168 = weekly) for quieter alerting, lower it for more frequent
    reminders on still-active findings.
  EOT
  type        = number
  default     = 24
}

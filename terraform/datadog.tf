resource "datadog_monitor" "redmine_http_health" {
  name = "project-77 redmine http health"
  type = "service check"

  query = "\"http.can_connect\".over(\"instance:redmine-http-local\").by(\"host\").last(2).count_by_status()"

  message = <<-EOT
  Redmine health check is failing on one or more web nodes.
  Please verify app container and DB connectivity.
  EOT

  include_tags   = true
  notify_no_data = false
  tags = [
    "project:77",
    "service:redmine",
    "env:study"
  ]

  monitor_thresholds {
    ok       = 1
    warning  = 1
    critical = 1
  }
}

variable "ansible_inventory_path" {
  description = "Path to Ansible inventory file"
  type        = string
  default     = "../ansible/inventory.ini"
}

variable "ansible_playbook_deploy" {
  description = "Playbook that configures application + DB + LB + monitoring"
  type        = string
  default     = "../ansible/playbook.yml"
}

variable "ansible_playbook_destroy" {
  description = "Playbook that tears down application + DB + LB + monitoring"
  type        = string
  default     = "../ansible/destroy.yml"
}

variable "vault_password_file" {
  description = "Ansible Vault password file (local, not committed)"
  type        = string
  default     = "../.vault_pass"
  sensitive   = true
}

variable "redmine_domain" {
  description = "Application domain name pointed to load balancer"
  type        = string
  default     = "example.com"
}

variable "load_balancer_ip" {
  description = "Public IP for DNS A-record (VPS из схемы relay, как в project-76), не приватный IP lb-1"
  type        = string
  default     = "192.168.2.5"
}

variable "datadog_api_key" {
  description = "Datadog API key for provider authentication"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog APP key for provider authentication"
  type        = string
  sensitive   = true
}

variable "datadog_api_url" {
  description = "Datadog API endpoint URL (site dependent)"
  type        = string
  default     = "https://api.datadoghq.com/"
}

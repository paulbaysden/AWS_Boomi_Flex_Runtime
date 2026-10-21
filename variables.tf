variable "config_file" {
  description = "Path to the YAML config file."
  type        = string
  default     = "config.yaml"
}

variable "install_token" {
  description = "Install token from the Runtime Management UI wizard. Valid for 15 minutes. Pass with TF_VAR_install_token."
  type        = string
  sensitive   = true
  default     = null
}

variable "run_install" {
  description = "Run runtimectl install. Set to false to create only the namespace and storage."
  type        = bool
  default     = true
}

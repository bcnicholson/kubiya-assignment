# variables.tf (root variables)

variable "output_path" {
  description = "Path to store the output files"
  type        = string
  default     = "./cluster-analysis"
}

variable "config_path" {
  description = "Path to the Kubernetes configuration file"
  type        = string
  default     = "~/.kube/config"
}

variable "config_context" {
  description = "Context to use in the Kubernetes configuration"
  type        = string
  default     = "minikube"
}

variable "include_resource_metrics" {
  description = "Whether to include resource usage metrics in the cluster analysis"
  type        = bool
  default     = false
}

variable "include_node_info" {
  description = "Whether to include node information in the output"
  type        = bool
  default     = false
}

variable "include_deployment_details" {
  description = "Whether to include deployment details in the output"
  type        = bool
  default     = false
}

variable "health_threshold" {
  description = "Percentage of running pods for the cluster to be considered healthy"
  type        = number
  default     = 90
}

variable "ignore_namespaces" {
  description = "List of namespaces to ignore in the analysis"
  type        = list(string)
  default     = ["kube-system", "kube-public", "kube-node-lease"]
}

variable "cluster_platform" {
  description = "Platform where the Kubernetes cluster is running"
  type        = string
  default     = "MacBook Pro M1 Max"
}

variable "cluster_cpu" {
  description = "CPU cores allocated to the Kubernetes cluster"
  type        = string
  default     = "6-Core CPU"
}

variable "cluster_memory" {
  description = "Memory allocated to the Kubernetes cluster"
  type        = string
  default     = "12GB"
}

variable "cluster_runtime" {
  description = "Kubernetes runtime (e.g., Docker, containerd)"
  type        = string
  default     = "Docker"
}

variable "analysis_type" {
  description = "Type of Kubernetes cluster analysis to perform"
  type        = string
  default     = "standard"
  validation {
    condition     = contains([
      "standard", "health", "performance", "security", 
      "troubleshooting", "comprehensive", "resource", "capacity"
    ], var.analysis_type)
    error_message = "Valid analysis types: standard, health, performance, security, troubleshooting, comprehensive, resource, capacity."
  }
}
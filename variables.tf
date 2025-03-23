# variables.tf (root variables)

variable "output_path" {
  description = "Path to store the output files"
  type        = string
  default     = "./cluster-analysis"
}

# Add these variables to your root variables.tf file

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
    condition     = contains(["standard", "health", "performance", "security", "troubleshooting", "comprehensive"], var.analysis_type)
    error_message = "Valid analysis types: standard, health, performance, security, troubleshooting, comprehensive."
  }
}
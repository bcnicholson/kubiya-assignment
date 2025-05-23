# modules/cluster-analyzer/variables.tf

#-----------------------------------------------------------------------------
# CORE CONFIGURATION VARIABLES
#-----------------------------------------------------------------------------

variable "output_path" {
  description = "Path where the output files will be stored"
  type        = string
}

#-----------------------------------------------------------------------------
# ANALYSIS CONFIGURATION OPTIONS
#-----------------------------------------------------------------------------

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

variable "include_resource_metrics" {
  description = "Whether to include resource metrics and utilization analysis in the output (requires metrics-server)"
  type        = bool
  default     = false
}

variable "health_threshold" {
  description = "Percentage of running pods for the cluster to be considered healthy"
  type        = number
  default     = 90
}

variable "ignore_namespaces" {
  description = "List of namespaces to ignore in the analysis, default set to K8s control plane namespaces"
  type        = list(string)
  default     = ["kube-system", "kube-public", "kube-node-lease"]
}

#-----------------------------------------------------------------------------
# ANALYSIS TYPE CONFIGURATION
#-----------------------------------------------------------------------------

variable "analysis_type" {
  description = "Type of Kubernetes cluster analysis to perform"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "health", "performance", "security", "troubleshooting", "comprehensive", "resource", "capacity"], var.analysis_type)
    error_message = "Valid analysis types: standard, health, performance, security, troubleshooting, comprehensive, resource, capacity."
  }
}

#-----------------------------------------------------------------------------
# CLUSTER METADATA VARIABLES
#-----------------------------------------------------------------------------

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

#-----------------------------------------------------------------------------
# DEBUGGING OPTIONS
#-----------------------------------------------------------------------------

variable "debug_mode" {
  description = "Whether to generate debug and raw metrics files"
  type        = bool
  default     = false
}
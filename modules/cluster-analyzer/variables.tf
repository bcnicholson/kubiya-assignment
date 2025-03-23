# modules/cluster-analyzer/variables.tf

variable "output_path" {
  description = "Path where the output files will be stored"
  type        = string
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
  description = "List of namespaces to ignore in the analysis, default set to K8s control plane namespaces"
  type        = list(string)
  default     = ["kube-system", "kube-public", "kube-node-lease"]
}
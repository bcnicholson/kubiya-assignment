# modules/cluster-analyzer/outputs.tf

#-----------------------------------------------------------------------------
# CORE CLUSTER INFORMATION
#-----------------------------------------------------------------------------

output "namespace_list" {
  description = "List of all namespaces in the cluster"
  value       = local.filtered_namespaces
}

# Use separate outputs for basic and enhanced summaries instead of a conditional
output "cluster_summary" {
  description = "Complete cluster health summary including pod count, status distribution, and namespace breakdown"
  value       = local.summary
}

output "enhanced_cluster_summary" {
  description = "Enhanced cluster summary with additional node and deployment information"
  value       = local.enhanced_summary
}

#-----------------------------------------------------------------------------
# POD STATUS OUTPUTS
#-----------------------------------------------------------------------------

output "running_pods_count" {
  description = "Number of pods that are in Running state"
  value       = local.base_summary.running_pods_count
}

output "problematic_pods_count" {
  description = "Number of pods that are not in Running or Succeeded state"
  value       = local.base_summary.problematic_pods_count
}

output "problematic_pods" {
  description = "Details of all pods that are not in Running or Succeeded state"
  value       = local.problematic_pods
}

output "pods_by_status" {
  description = "Grouping of pods by their status"
  value       = local.pods_by_status
}

output "pods_by_namespace" {
  description = "Grouping of pods by their namespace"
  value       = local.pods_by_namespace
}

#-----------------------------------------------------------------------------
# ENHANCED POD GROUPING OUTPUTS
#-----------------------------------------------------------------------------

output "pods_by_namespace_and_status" {
  description = "Two-level hierarchical grouping of pods (namespace → status → pods)"
  value       = local.pods_by_namespace_and_status
}

output "namespace_summary" {
  description = "Detailed summary of each namespace including pod names and status counts"
  value       = local.namespace_summary
}

output "status_summary" {
  description = "Detailed summary of each status including pod names and namespace counts"
  value       = local.status_summary
}

output "namespace_summary_path" {
  description = "Path to the namespace summary JSON file"
  value       = "${var.output_path}/namespace_summary.json"
}

output "status_summary_path" {
  description = "Path to the status summary JSON file"
  value       = "${var.output_path}/status_summary.json"
}

output "pods_by_namespace_and_status_path" {
  description = "Path to the hierarchical pod grouping JSON file"
  value       = "${var.output_path}/pods_by_namespace_and_status.json"
}

#-----------------------------------------------------------------------------
# HEALTH STATUS OUTPUTS
#-----------------------------------------------------------------------------

output "health_percentage" {
  description = "Percentage of pods in Running state"
  value       = local.health_percentage
}

output "health_threshold" {
  description = "Configured health threshold percentage"
  value       = var.health_threshold
}

output "is_healthy" {
  description = "Boolean indicating if the cluster meets the health threshold"
  value       = local.is_healthy
}

output "health_status" {
  description = "Simple health status (Healthy/Unhealthy) based on threshold"
  value       = local.is_healthy ? "Healthy" : "Unhealthy"
}

#-----------------------------------------------------------------------------
# AI ANALYSIS OUTPUTS
#-----------------------------------------------------------------------------

output "ai_prompt" {
  description = "Generated AI prompt for cluster health analysis"
  value       = (var.include_node_info || var.include_deployment_details) ? local.enhanced_ai_prompt : local.ai_prompt
}

#-----------------------------------------------------------------------------
# OUTPUT FILE PATHS
#-----------------------------------------------------------------------------

output "ai_prompt_path" {
  description = "Path to the file containing the AI prompt for analysis"
  value       = "${var.output_path}/ai_prompt.md"
}

output "raw_pod_data_path" {
  description = "Path to the raw pod data JSON file"
  value       = "${var.output_path}/raw_pod_data.json"
}

output "cluster_summary_path" {
  description = "Path to the cluster summary JSON file"
  value       = "${var.output_path}/cluster_summary.json"
}

output "problematic_pods_path" {
  description = "Path to the problematic pods JSON file"
  value       = "${var.output_path}/problematic_pods.json"
}

output "health_status_path" {
  description = "Path to the health status JSON file"
  value       = "${var.output_path}/health_status.json"
}

#-----------------------------------------------------------------------------
# OPTIONAL OUTPUTS (NODE & DEPLOYMENT)
#-----------------------------------------------------------------------------

output "node_data" {
  description = "Information about cluster nodes (if enabled)"
  value       = var.include_node_info ? local.nodes : null
}

output "deployment_data" {
  description = "Information about deployments (if enabled)"
  value       = var.include_deployment_details ? local.all_deployments : null
}

output "problematic_deployments" {
  description = "Details of deployments not meeting replica requirements (if enabled)"
  value       = var.include_deployment_details ? (local.enhanced_summary.problematic_deployments != null ? local.enhanced_summary.problematic_deployments : []) : []
}

output "node_data_path" {
  description = "Path to the node data JSON file (if enabled)"
  value       = var.include_node_info ? "${var.output_path}/node_data.json" : null
}

output "deployment_data_path" {
  description = "Path to the deployment data JSON file (if enabled)"
  value       = var.include_deployment_details ? "${var.output_path}/deployment_data.json" : null
}
# modules/cluster-analyzer/main.tf

#-----------------------------------------------------------------------------
# PROVIDER CONFIGURATION
#-----------------------------------------------------------------------------

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

#-----------------------------------------------------------------------------
# DATA SOURCES
#-----------------------------------------------------------------------------

# Fetch all namespaces and filter based on ignore list
data "kubernetes_all_namespaces" "allns" {}

locals {
  filtered_namespaces = [
    for ns in data.kubernetes_all_namespaces.allns.namespaces : ns
    if !contains(var.ignore_namespaces, ns)
  ]
}

# Fetch pod information from filtered namespaces
data "kubernetes_resources" "all_pods" {
  for_each    = toset(local.filtered_namespaces)
  api_version = "v1"
  kind        = "Pod"
  namespace   = each.value
}

# Fetch node information (optional)
data "kubernetes_resources" "nodes" {
  count       = var.include_node_info ? 1 : 0
  api_version = "v1"
  kind        = "Node"
}

# Fetch deployment information (optional)
data "kubernetes_resources" "deployments" {
  for_each    = var.include_deployment_details ? toset(local.filtered_namespaces) : []
  api_version = "apps/v1"
  kind        = "Deployment"
  namespace   = each.value
}

#-----------------------------------------------------------------------------
# POD DATA PROCESSING
#-----------------------------------------------------------------------------

locals {
  # Process all pods into a normalized format
  all_pods = flatten([
    for namespace, resource in data.kubernetes_resources.all_pods : [
      for pod in resource.objects : {
        name      = pod.metadata.name
        namespace = pod.metadata.namespace
        status    = pod.status.phase
        containers = [
          for container in pod.spec.containers : {
            name   = container.name
            image  = container.image
            ready  = try(
              [for status in pod.status.containerStatuses : status.ready if status.name == container.name][0],
              false
            )
          }
        ]
        node_name = try(pod.spec.nodeName, "unknown")
        pod_ip    = try(pod.status.podIP, "unknown")
        conditions = try([
          for condition in pod.status.conditions : {
            type   = condition.type
            status = condition.status
          }
        ], [])
        start_time = try(pod.status.startTime, "unknown")
      }
    ]
  ])

  # Enhanced pod groupings - two-level structure (namespace → status → pods)
  pods_by_namespace_and_status = {
    for namespace in local.filtered_namespaces : namespace => {
      for status in distinct([for pod in local.all_pods : pod.status if pod.namespace == namespace]) : status => [
        for pod in local.all_pods : {
          name = pod.name
          containers = pod.containers
          node = pod.node_name
          start_time = pod.start_time
        } if pod.namespace == namespace && pod.status == status
      ]
    } if length([for pod in local.all_pods : pod if pod.namespace == namespace]) > 0
  }

# More detailed namespace summary with pod names
  namespace_summary = {
    for namespace in local.filtered_namespaces : namespace => {
      total_pods = length([for pod in local.all_pods : pod if pod.namespace == namespace]),
      pod_names = [for pod in local.all_pods : pod.name if pod.namespace == namespace],
      status_counts = {
        for status in distinct([for pod in local.all_pods : pod.status if pod.namespace == namespace]) : status => length(
          [for pod in local.all_pods : pod if pod.namespace == namespace && pod.status == status]
        )
      }
    } if length([for pod in local.all_pods : pod if pod.namespace == namespace]) > 0
  }

# More detailed status summary with pod names
  status_summary = {
    for status in distinct([for pod in local.all_pods : pod.status]) : status => {
      total_pods = length([for pod in local.all_pods : pod if pod.status == status]),
      pod_names = [for pod in local.all_pods : pod.name if pod.status == status],
      namespace_counts = {
        for namespace in distinct([for pod in local.all_pods : pod.namespace if pod.status == status]) : namespace => length(
          [for pod in local.all_pods : pod if pod.status == status && pod.namespace == namespace]
        )
      }
    }
  }

  # Organize pods by namespace and status
  pods_by_namespace = {
    for pod in local.all_pods : pod.namespace => pod...
  }

  pods_by_status = {
    for pod in local.all_pods : pod.status => pod...
  }

  # Identify problematic pods
  problematic_pods = [
    for pod in local.all_pods : pod if !contains(["Running", "Succeeded"], pod.status)
  ]
}

#-----------------------------------------------------------------------------
# NODE & DEPLOYMENT DATA PROCESSING (OPTIONAL)
#-----------------------------------------------------------------------------

locals {
  # Process node information
  nodes = var.include_node_info ? [
    for node in try(data.kubernetes_resources.nodes[0].objects, []) : {
      name       = node.metadata.name
      capacity   = try(node.status.capacity, {})
      conditions = try([
        for condition in node.status.conditions : {
          type    = condition.type
          status  = condition.status
          reason  = try(condition.reason, "")
          message = try(condition.message, "")
        }
      ], [])
      addresses = try([
        for address in node.status.addresses : {
          type    = address.type
          address = address.address
        }
      ], [])
      kubelet_version = try(node.status.nodeInfo.kubeletVersion, "unknown")
    }
  ] : []

  # Process deployment information
  all_deployments = var.include_deployment_details ? flatten([
    for namespace, resource in data.kubernetes_resources.deployments : [
      for deployment in resource.objects : {
        name                 = deployment.metadata.name
        namespace            = deployment.metadata.namespace
        replicas             = try(deployment.spec.replicas, 0)
        available_replicas   = try(deployment.status.availableReplicas, 0)
        unavailable_replicas = try(deployment.status.unavailableReplicas, 0)
        ready_replicas       = try(deployment.status.readyReplicas, 0)
        strategy             = try(deployment.spec.strategy.type, "unknown")
        selector             = try(deployment.spec.selector.matchLabels, {})
      }
    ]
  ]) : []
}

#-----------------------------------------------------------------------------
# SUMMARY GENERATION
#-----------------------------------------------------------------------------

locals {
  # Base summary with core metrics
  base_summary = {
    total_pods                 = length(local.all_pods)
    namespaces_count           = length(local.filtered_namespaces)
    namespaces                 = local.filtered_namespaces
    filtered_namespaces_count  = length(data.kubernetes_all_namespaces.allns.namespaces) - length(local.filtered_namespaces)
    ignored_namespaces         = var.ignore_namespaces
    running_pods_count         = length([for pod in local.all_pods : pod if pod.status == "Running"])
    problematic_pods_count     = length(local.problematic_pods)
    pods_by_status_count       = {
      for status, pods in local.pods_by_status : status => length(pods)
    }
    pods_by_namespace_count    = {
      for namespace, pods in local.pods_by_namespace : namespace => length(pods)
    }
    timestamp                  = timestamp()
  }

  # Enhanced summary with optional node and deployment data
  enhanced_base_summary = merge(local.base_summary, {
    # Node information (if enabled)
    nodes_count = length(local.nodes)
    nodes = var.include_node_info ? {
      for node in local.nodes : node.name => {
        capacity        = node.capacity
        status          = {
          for condition in node.conditions : condition.type => condition.status if condition.type == "Ready"
        }
        kubelet_version = node.kubelet_version
      }
    } : {}
    
    # Deployment information (if enabled)
    deployments_count = length(local.all_deployments)
    deployments = var.include_deployment_details ? {
      for deployment in local.all_deployments : "${deployment.namespace}/${deployment.name}" => {
        namespace          = deployment.namespace
        replicas           = deployment.replicas
        available_replicas = deployment.available_replicas
        ready_replicas     = deployment.ready_replicas
        health_percent     = deployment.replicas > 0 ? (deployment.ready_replicas / deployment.replicas) * 100 : 0
      }
    } : {}
    
    # Problematic deployments (if enabled)
    problematic_deployments = var.include_deployment_details ? [
      for deployment in local.all_deployments : {
        name      = deployment.name
        namespace = deployment.namespace
        replicas  = deployment.replicas
        available = deployment.available_replicas
        ready     = deployment.ready_replicas
        reason    = "Deployment has unavailable replicas"
      } if deployment.replicas > deployment.ready_replicas
    ] : []
  })
}

#-----------------------------------------------------------------------------
# HEALTH METRICS CALCULATION
#-----------------------------------------------------------------------------

locals {
  # Calculate health metrics
  health_percentage = local.base_summary.total_pods > 0 ? floor((local.base_summary.running_pods_count / local.base_summary.total_pods) * 100 * 100) / 100 : 100
  # Determine if cluster meets health threshold
  is_healthy = local.health_percentage >= var.health_threshold

  # Add health metrics to summaries
  summary = merge(local.base_summary, {
    health_percentage = local.health_percentage
    health_threshold  = var.health_threshold
    health_status     = local.is_healthy ? "Healthy" : "Unhealthy"
  })

  enhanced_summary = merge(local.enhanced_base_summary, {
    health_percentage = local.health_percentage
    health_threshold  = var.health_threshold
    health_status     = local.is_healthy ? "Healthy" : "Unhealthy"
  })
}

#-----------------------------------------------------------------------------
# AI PROMPTS GENERATION
#-----------------------------------------------------------------------------

locals {
  # Standard AI prompt for basic analysis
  ai_prompt = <<-EOT
  # Kubernetes Cluster Health Analysis Request

  ## Cluster Overview
  - Total pods: ${local.base_summary.total_pods}
  - Total namespaces (after filtering): ${local.base_summary.namespaces_count}
  - Ignored namespaces: ${join(", ", local.base_summary.ignored_namespaces)}
  - Running pods: ${local.base_summary.running_pods_count}
  - Problematic pods: ${local.base_summary.problematic_pods_count}
  - Health percentage: ${format("%.1f", local.health_percentage)}% (threshold: ${var.health_threshold}%)
  - Overall status: ${local.is_healthy ? "Healthy" : "Unhealthy"}

  ## Pods by Status
  ${join("\n", [for status, info in local.status_summary : "- ${status}: ${info.total_pods} pods (${join(", ", info.pod_names)})"])}

  ## Pods by Namespace
  ${join("\n", [for namespace, info in local.namespace_summary : "- ${namespace}: ${info.total_pods} pods (${join(", ", info.pod_names)})"])}

  ## Detailed Namespace and Status Breakdown
  ${join("\n", [
    for namespace, statuses in local.pods_by_namespace_and_status : <<-NAMESPACE
    - Namespace: ${namespace}
      ${join("\n  ", [
        for status, pods in statuses : "- ${status}: ${length(pods)} pods (${join(", ", [for pod in pods : pod.name])})"
      ])}
    NAMESPACE
  ])}

  ## Problematic Pods Details
  ${length(local.problematic_pods) > 0 ? join("\n", [
    for pod in local.problematic_pods : <<-POD
    - Pod '${pod.name}' in namespace '${pod.namespace}':
      - Status: ${pod.status}
      - Node: ${pod.node_name}
      - Pod IP: ${pod.pod_ip}
      - Start Time: ${pod.start_time}
      - Containers:
        ${join("\n        ", [
          for container in pod.containers : "- ${container.name} (${container.image}): ${container.ready ? "Ready" : "Not Ready"}"
        ])}
      - Conditions:
        ${length(pod.conditions) > 0 ? join("\n        ", [
          for condition in pod.conditions : "- ${condition.type}: ${condition.status}"
        ]) : "        - No conditions available"}
    POD
  ]) : "No problematic pods found."}

  ## Analysis Request
  Based on the information above:
  1. Please analyze the overall health of this Kubernetes cluster. The configured health threshold is ${var.health_threshold}% of pods in Running state - is the cluster meeting this requirement?
  2. Identify any issues or concerns based on the pod statuses.
  3. For each problematic pod, diagnose the likely cause of the issue and suggest specific solutions based on the detailed information provided.
  4. Provide a general assessment of the cluster configuration based on the namespace and pod distribution.
  5. Are there any potential bottlenecks or resource constraints that might be indicated by this data?

  This analysis will be used to improve the cluster's stability and performance.
  EOT

  # Enhanced AI prompt with optional node and deployment information
  enhanced_ai_prompt = <<-EOT
  # Kubernetes Cluster Health Analysis Request

  ## Cluster Overview
  - Total pods: ${local.base_summary.total_pods}
  - Total namespaces (after filtering): ${local.base_summary.namespaces_count}
  - Ignored namespaces: ${join(", ", var.ignore_namespaces)}
  - Running pods: ${local.base_summary.running_pods_count}
  - Problematic pods: ${local.base_summary.problematic_pods_count}
  - Health percentage: ${format("%.1f", local.health_percentage)}% (threshold: ${var.health_threshold}%)
  - Overall status: ${local.is_healthy ? "Healthy" : "Unhealthy"}
  ${var.include_node_info ? "- Total nodes: ${length(local.nodes)}" : ""}
  ${var.include_deployment_details ? "- Total deployments: ${length(local.all_deployments)}" : ""}
  ${var.include_deployment_details ? "- Problematic deployments: ${length(local.enhanced_summary.problematic_deployments)}" : ""}

  ## Pods by Status
  ${join("\n", [for status, info in local.status_summary : "- ${status}: ${info.total_pods} pods (${join(", ", info.pod_names)})"])}

  ## Pods by Namespace
  ${join("\n", [for namespace, count in local.base_summary.pods_by_namespace_count : "- ${namespace}: ${count}"])}

  ## Detailed Namespace and Status Breakdown
  ${join("\n", [
    for namespace, statuses in local.pods_by_namespace_and_status : <<-NAMESPACE
    - Namespace: ${namespace}
      ${join("\n  ", [
        for status, pods in statuses : "- ${status}: ${length(pods)} pods (${join(", ", [for pod in pods : pod.name])})"
      ])}
    NAMESPACE
  ])}

  ## Problematic Pods Details
  ${length(local.problematic_pods) > 0 ? join("\n", [
    for pod in local.problematic_pods : <<-POD
    - Pod '${pod.name}' in namespace '${pod.namespace}':
      - Status: ${pod.status}
      - Node: ${pod.node_name}
      - Pod IP: ${pod.pod_ip}
      - Start Time: ${pod.start_time}
      - Containers:
        ${join("\n        ", [
          for container in pod.containers : "- ${container.name} (${container.image}): ${container.ready ? "Ready" : "Not Ready"}"
        ])}
      - Conditions:
        ${length(pod.conditions) > 0 ? join("\n        ", [
          for condition in pod.conditions : "- ${condition.type}: ${condition.status}"
        ]) : "        - No conditions available"}
    POD
  ]) : "No problematic pods found."}

  ${var.include_node_info ? "## Node Information\n${join("\n", [for node in local.nodes : "- Node '${node.name}' running kubelet ${node.kubelet_version}. Ready: ${try(node.conditions[index(node.conditions.*.type, "Ready")].status, "Unknown")}, Memory: ${try(node.capacity.memory, "Unknown")}, CPU: ${try(node.capacity.cpu, "Unknown")}"])}" : ""}

  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? "## Problematic Deployments\n${join("\n", [
    for deployment in local.enhanced_summary.problematic_deployments : <<-DEPLOYMENT
    - Deployment '${deployment.name}' in namespace '${deployment.namespace}':
      - Replicas: ${deployment.replicas}
      - Available: ${deployment.available}
      - Ready: ${deployment.ready}
      - Health %: ${(deployment.ready / deployment.replicas) * 100}%
      - Issue: ${deployment.reason}
    DEPLOYMENT
  ])}" : var.include_deployment_details ? "## Deployments\nAll deployments are healthy with expected number of replicas." : ""}

  ## Analysis Request
  Based on the information above:
  1. Please analyze the overall health of this Kubernetes cluster. The configured health threshold is ${var.health_threshold}% of pods in Running state - is the cluster meeting this requirement?
  2. Identify any issues or concerns based on the pod statuses${var.include_deployment_details ? " and deployment replicas" : ""}.
  3. For each problematic pod${var.include_deployment_details ? " and deployment" : ""}, diagnose the likely cause of the issue and suggest specific solutions based on the detailed information provided.
  4. Provide a general assessment of the cluster configuration based on the namespace and pod distribution.
  5. Are there any potential bottlenecks or resource constraints that might be indicated by this data?
  ${var.include_node_info ? "6. Evaluate the node capacity relative to the workload. Is the cluster appropriately sized?" : ""}

  This analysis will be used to improve the cluster's stability and performance.
  EOT
}

#-----------------------------------------------------------------------------
# OUTPUT FILE GENERATION
#-----------------------------------------------------------------------------

# Create output directory if it doesn't exist
resource "local_file" "ensure_output_dir" {
  content     = "# This directory contains Kubernetes cluster analysis files generated by Terraform"
  filename    = "${var.output_path}/.keep"
  
  provisioner "local-exec" {
    command = "mkdir -p ${var.output_path}"
  }
}

# Generate base output files
resource "local_file" "raw_pod_data" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.all_pods)
  filename   = "${var.output_path}/raw_pod_data.json"
}

resource "local_file" "cluster_summary" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.summary)
  filename   = "${var.output_path}/cluster_summary.json"
}

resource "local_file" "health_status" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode({
    timestamp          = local.base_summary.timestamp,
    health_percentage  = local.health_percentage,
    health_threshold   = var.health_threshold,
    is_healthy         = local.is_healthy,
    running_pods       = local.base_summary.running_pods_count,
    total_pods         = local.base_summary.total_pods,
    problematic_pods_count = local.base_summary.problematic_pods_count
  })
  filename   = "${var.output_path}/health_status.json"
}

# Output detailed namespace grouping to a file
resource "local_file" "namespace_summary" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.namespace_summary)
  filename   = "${var.output_path}/namespace_summary.json"
}

# Output detailed status grouping to a file
resource "local_file" "status_summary" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.status_summary)
  filename   = "${var.output_path}/status_summary.json"
}

# Output hierarchical namespace->status->pods grouping
resource "local_file" "pods_by_namespace_and_status" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.pods_by_namespace_and_status)
  filename   = "${var.output_path}/pods_by_namespace_and_status.json"
}

# Output detailed data for any problematic pods
resource "local_file" "problematic_pods" {
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.problematic_pods)
  filename   = "${var.output_path}/problematic_pods.json"
}

# Generate optional output files
resource "local_file" "node_data" {
  count      = var.include_node_info ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.nodes)
  filename   = "${var.output_path}/node_data.json"
}

resource "local_file" "deployment_data" {
  count      = var.include_deployment_details ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.all_deployments)
  filename   = "${var.output_path}/deployment_data.json"
}

# Generate AI prompt
resource "local_file" "ai_prompt" {
  depends_on = [local_file.ensure_output_dir]
  content    = (var.include_node_info || var.include_deployment_details) ? local.enhanced_ai_prompt : local.ai_prompt
  filename   = "${var.output_path}/ai_prompt.md"
}
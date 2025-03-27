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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

# Fetch events for problematic pods to enhance root cause analysis
data "kubernetes_resources" "pod_events" {
  depends_on = [data.kubernetes_resources.all_pods]
  
  for_each = {
    for i, pod in local.problematic_pods : "${pod.namespace}/${pod.name}" => pod
    if !contains(["Running", "Succeeded"], pod.status)
  }
  
  api_version = "v1"
  kind        = "Event"
  namespace   = each.value.namespace
  
  field_selector = "involvedObject.name=${each.value.name}"
}

# Enhanced problematic pods with event data
locals {
  problematic_pods_with_events = [
    for pod in local.problematic_pods : merge(pod, {
      events = try(
        [for event in try(data.kubernetes_resources.pod_events["${pod.namespace}/${pod.name}"].objects, []) : {
          type    = try(event.type, "Unknown")
          reason  = try(event.reason, "Unknown")
          message = try(event.message, "No message")
          count   = try(event.count, 0)
          time    = try(event.lastTimestamp, "Unknown")
          first_time = try(event.firstTimestamp, "Unknown")
        }],
        []
      )
    })
  ]
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

# Fetch pod metrics if enabled - using direct API path
resource "null_resource" "get_pod_metrics" {
  count = var.include_resource_metrics ? 1 : 0
  
  triggers = {
    timestamp = timestamp()
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Fetching pod metrics from API..."
      kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods > ${var.output_path}/raw_pod_metrics.json || echo "Failed to get raw pod metrics"
    EOT
  }
}

# Read the raw pod metrics file
data "local_file" "raw_pod_metrics" {
  depends_on = [null_resource.get_pod_metrics]
  count      = var.include_resource_metrics ? 1 : 0
  filename   = "${var.output_path}/raw_pod_metrics.json"
}

# Fetch node metrics if enabled and node info is included
data "kubernetes_resources" "node_metrics" {
  count       = var.include_resource_metrics && var.include_node_info ? 1 : 0
  api_version = "metrics.k8s.io/v1beta1"
  kind        = "NodeMetrics"
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
            # Add resource requests/limits
            resources = {
              requests = try({
                cpu    = container.resources.requests.cpu,
                memory = container.resources.requests.memory
              }, null)
              limits = try({
                cpu    = container.resources.limits.cpu,
                memory = container.resources.limits.memory
              }, null)
            }
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

  # Define the empty metrics structure with all expected fields
  empty_metrics_list = {
    kind: "PodMetricsList",
    apiVersion: "metrics.k8s.io/v1beta1",
    metadata: {},
    items: []
  }
  
  # Process pod metrics with namespace filtering - correctly handling PodMetricsList structure
  raw_pod_metrics_list = var.include_resource_metrics ? try(jsondecode(data.local_file.raw_pod_metrics[0].content), local.empty_metrics_list) : local.empty_metrics_list
  
  # Process pod metrics with namespace filtering
  pod_metrics = var.include_resource_metrics ? {
    for pod_metric in try(local.raw_pod_metrics_list.items, []) : 
    "${pod_metric.metadata.namespace}/${pod_metric.metadata.name}" => {
      namespace  = pod_metric.metadata.namespace
      name       = pod_metric.metadata.name
      containers = {
        for container in try(pod_metric.containers, []) : container.name => {
          cpu    = try(container.usage.cpu, "0")
          memory = try(container.usage.memory, "0")
        }
      }
      timestamp = try(pod_metric.timestamp, timestamp())
    } if !contains(var.ignore_namespaces, pod_metric.metadata.namespace)
  } : {}

  # Process node metrics if enabled
  node_metrics = var.include_resource_metrics && var.include_node_info ? {
    for node_metric in try(data.kubernetes_resources.node_metrics[0].objects, []) : node_metric.metadata.name => {
      name      = node_metric.metadata.name
      cpu       = node_metric.usage.cpu
      memory    = node_metric.usage.memory
      timestamp = node_metric.timestamp
    }
  } : {}

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
# RESOURCE METRICS CALCULATION (OPTIONAL)
#-----------------------------------------------------------------------------

locals {
  # Create a pod resource utilization structure with basic calculations
  pod_resource_utilization = var.include_resource_metrics ? {
    for key, pod in local.pod_metrics : key => {
      namespace = pod.namespace
      name = pod.name
      containers = {
        for container_name, container in pod.containers : container_name => {
          # Basic metrics data 
          cpu_usage = container.cpu
          memory_usage = container.memory
          
          # Find matching pod and container to get resource data
          cpu_request = try(
            [for p in local.all_pods : 
              [for c in p.containers : 
                try(c.resources.requests.cpu, null)
                if c.name == container_name
              ][0]
              if p.namespace == pod.namespace && p.name == pod.name
            ][0],
            null
          )
          memory_request = try(
            [for p in local.all_pods : 
              [for c in p.containers : 
                try(c.resources.requests.memory, null)
                if c.name == container_name
              ][0]
              if p.namespace == pod.namespace && p.name == pod.name
            ][0],
            null
          )
          cpu_limit = try(
            [for p in local.all_pods : 
              [for c in p.containers : 
                try(c.resources.limits.cpu, null)
                if c.name == container_name
              ][0]
              if p.namespace == pod.namespace && p.name == pod.name
            ][0],
            null
          )
          memory_limit = try(
            [for p in local.all_pods : 
              [for c in p.containers : 
                try(c.resources.limits.memory, null)
                if c.name == container_name
              ][0]
              if p.namespace == pod.namespace && p.name == pod.name
            ][0],
            null
          )

          # Simple utilization values
          # Maintaining these as null since complex calculations were causing errors
          # Revisit and add back in if time allows, otherwise will revisit in future
          cpu_utilization_vs_request = null
          memory_utilization_vs_request = null
          cpu_utilization_vs_limit = null
          memory_utilization_vs_limit = null
        }
      }
    }
  } : {}
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

 # Enhanced summary with optional node, deployment, and resource metrics data
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
    
    # Resource metrics (if enabled) - simplified approach (For root main.tf output)
    resource_metrics_available = var.include_resource_metrics
    pods_with_metrics = var.include_resource_metrics ? length(local.pod_metrics) : 0
    
    # Simple count of pods with CPU usage - use a fixed threshold for "high"
    pods_with_high_cpu = var.include_resource_metrics ? length([
      for key, pod in local.pod_metrics : pod 
      if try(
        !startswith(pod.containers[keys(pod.containers)[0]].cpu, "0") && 
        replace(pod.containers[keys(pod.containers)[0]].cpu, "n", "") != "" &&
        contains(["n", "m"], substr(pod.containers[keys(pod.containers)[0]].cpu, -1, 1))
      , false)
    ]) : 0
    
    # Simple count of pods with memory usage - use a fixed threshold for "high"
    pods_with_high_memory = var.include_resource_metrics ? length([
      for key, pod in local.pod_metrics : pod 
      if try(
        !startswith(pod.containers[keys(pod.containers)[0]].memory, "0") &&
        (
          (endswith(pod.containers[keys(pod.containers)[0]].memory, "Mi") && 
           tonumber(replace(pod.containers[keys(pod.containers)[0]].memory, "Mi", "")) > 50) ||
          (endswith(pod.containers[keys(pod.containers)[0]].memory, "Ki") && 
           tonumber(replace(pod.containers[keys(pod.containers)[0]].memory, "Ki", "")) > 50000)
        )
      , false)
    ]) : 0
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
    root_causes       = {
      for pod in local.problematic_pods_with_events : pod.name => {
        status = pod.status
        events = [
          for event in try(pod.events, []) : {
            reason = event.reason
            message = event.message
          }
        ]
        likely_cause = try(length(pod.events) > 0, false) ? try(pod.events[0].reason, "Unknown") : (
          pod.status == "Pending" ? "Scheduling or Resource Issue" : (
            pod.status == "Failed" ? "Container Error" : "Unknown"
          )
        )
      }
    }
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
  # Add cluster context information to be included in all prompts
  cluster_context = <<-EOT
  ## K8s Deployment Context
  - Environment: Minikube on ${var.cluster_platform}
  - Expected SLAs: ${var.health_threshold}%
  - Hardware: ${var.cluster_cpu} CPU, ${var.cluster_memory} memory
  - Analysis timestamp: ${local.base_summary.timestamp}
  EOT

  # Standard AI prompt for basic analysis
  ai_prompt = <<-EOT
  # Kubernetes Cluster Health Analysis

  ${local.cluster_context}

  ## Cluster Summary
  - Total pods: ${local.base_summary.total_pods}
  - Namespaces: ${local.base_summary.namespaces_count} (filtered from ${local.base_summary.namespaces_count + local.base_summary.filtered_namespaces_count})
  - Health status: ${local.is_healthy ? "HEALTHY ✓" : "UNHEALTHY ⚠️"} (${format("%.1f", local.health_percentage)}% healthy, threshold: ${var.health_threshold}%)
  - Running pods: ${local.base_summary.running_pods_count}/${local.base_summary.total_pods}
  - Problematic pods: ${local.base_summary.problematic_pods_count}

  ## Status Distribution
  ${join("\n", [for status, info in local.status_summary : "- ${status}: ${info.total_pods} pods"])}

  ## Namespace Distribution
  ${join("\n", [
    for namespace, info in local.namespace_summary : <<-NAMESPACE
    - ${namespace}: ${info.total_pods} pods
      - Status breakdown: ${join(", ", [for status, count in info.status_counts : "${status}: ${count}"])}
    NAMESPACE
  ])}

  ## Problematic Pods
  ${length(local.problematic_pods_with_events) > 0 ? join("\n", [
    for pod in local.problematic_pods_with_events : <<-POD
    - Pod '${pod.name}' in namespace '${pod.namespace}':
      - Status: ${pod.status}
      - Node: ${pod.node_name}
      - Start time: ${pod.start_time}
      - Containers: ${join(", ", [for container in pod.containers : "${container.name} (${container.ready ? "Ready" : "Not Ready"})"])}
      - Events:
        ${try(length(pod.events) > 0, false) ? join("\n    ", [
          for event in try(pod.events, []) : "- ${event.reason}: ${event.message} (${event.count} times, last occurred at ${event.time})"
      ]) : "      No events found."}
    POD
  ]) : "No problematic pods found."}
  
  ## Analysis Request
  As a Kubernetes expert, please analyze this cluster and provide:

  1. Health Assessment:
     - Is the cluster meeting its ${var.health_threshold}% health threshold requirement?
     - What is the overall health rating (Healthy/Degraded/Critical)?

  2. Issue Investigation:
     - For each problematic pod, what is the most likely cause?
     - What specific steps would you recommend to resolve these issues?

  3. Recommendations:
     - What improvements to the cluster configuration would you suggest?
     - Are there any potential resource constraints or bottlenecks?

  Format your response as a concise report with clearly labeled sections for:
  - Summary (1-2 sentences on overall status)
  - Issues (prioritized list with diagnostics)
  - Resolution Steps (with specific kubectl commands where applicable)
  - Recommendations (2-3 key suggestions for improvement)
  EOT
  
  # Enhanced AI prompt with optional node and deployment information
  enhanced_ai_prompt = <<-EOT
  # Kubernetes Cluster Analysis with Node and Deployment Information

  ${local.cluster_context}

  ## Cluster Health Summary
  - Total pods: ${local.base_summary.total_pods}
  - Namespaces: ${local.base_summary.namespaces_count} (filtered from ${local.base_summary.namespaces_count + local.base_summary.filtered_namespaces_count})
  - Health status: ${local.is_healthy ? "HEALTHY ✓" : "UNHEALTHY ⚠️"} (${format("%.1f", local.health_percentage)}% healthy, threshold: ${var.health_threshold}%)
  - Running pods: ${local.base_summary.running_pods_count}/${local.base_summary.total_pods}
  - Problematic pods: ${local.base_summary.problematic_pods_count}
  ${var.include_node_info ? "- Total nodes: ${length(local.nodes)}" : ""}
  ${var.include_deployment_details ? "- Total deployments: ${length(local.all_deployments)}" : ""}
  ${var.include_deployment_details ? "- Problematic deployments: ${length(local.enhanced_summary.problematic_deployments)}" : ""}
  ${var.include_resource_metrics ? "- Pods with resource metrics: ${length(local.pod_metrics)}" : ""}
  ${var.include_resource_metrics ? "- Pods with high CPU utilization: ${local.enhanced_summary.pods_with_high_cpu}" : ""}
  ${var.include_resource_metrics ? "- Pods with high memory utilization: ${local.enhanced_summary.pods_with_high_memory}" : ""}

  ## Resource Distribution
  ${join("\n", [for namespace, count in local.base_summary.pods_by_namespace_count : "- Namespace '${namespace}': ${count} pods"])}

  ## Status Distribution
  ${join("\n", [for status, info in local.status_summary : "- ${status}: ${info.total_pods} pods"])}

  ## Problematic Resources
  ${length(local.problematic_pods_with_events) > 0 ? "### Problematic Pods\n" : ""}
  ${length(local.problematic_pods_with_events) > 0 ? join("\n", [
    for pod in local.problematic_pods_with_events : <<-POD
    - Pod '${pod.name}' in namespace '${pod.namespace}':
      - Status: ${pod.status}
      - Node: ${pod.node_name}
      - Start Time: ${pod.start_time}
      - Events:
        ${try(length(pod.events) > 0, false) ? join("\n    ", [
          for event in try(pod.events, []) : "- ${event.reason}: ${event.message} (${event.count} times, last occurred at ${event.time})"
      ]) : "      No events found."}
      - Containers:
        ${join("\n      ", [
          for container in pod.containers : <<-CONTAINER
          - ${container.name} (${container.image}): ${container.ready ? "Ready" : "Not Ready"}
            ${var.include_resource_metrics ? try(<<-METRICS
            - Resources:
              - CPU Request: ${try(container.resources.requests.cpu, "None")}
              - Memory Request: ${try(container.resources.requests.memory, "None")}
              - CPU Limit: ${try(container.resources.limits.cpu, "None")}
              - Memory Limit: ${try(container.resources.limits.memory, "None")}
              - CPU Usage: ${try(local.pod_metrics["${pod.namespace}/${pod.name}"].containers[container.name].cpu, "No metrics")}
              - Memory Usage: ${try(local.pod_metrics["${pod.namespace}/${pod.name}"].containers[container.name].memory, "No metrics")}
            METRICS
            , "") : ""}
          CONTAINER
        ])}
      - Conditions:
        ${length(pod.conditions) > 0 ? join("\n      ", [
          for condition in pod.conditions : "- ${condition.type}: ${condition.status}"
        ]) : "      - No conditions available"}
    POD
  ]) : "No problematic pods found."}

  ${var.include_node_info ? "## Node Information\n" : ""}
  ${var.include_node_info ? join("\n", [for node in local.nodes : <<-NODE
  - Node '${node.name}':
    - Kubelet: ${node.kubelet_version}
    - Ready: ${try(node.conditions[index(node.conditions.*.type, "Ready")].status, "Unknown")}
    - Capacity: CPU: ${try(node.capacity.cpu, "Unknown")}, Memory: ${try(node.capacity.memory, "Unknown")}
    - Pod count: ${length([for pod in local.all_pods : pod if pod.node_name == node.name])}
    ${var.include_resource_metrics ? try(<<-METRICS
    - Resource Usage:
      - CPU: ${try(local.node_metrics[node.name].cpu, "No metrics")}
      - Memory: ${try(local.node_metrics[node.name].memory, "No metrics")}
    METRICS
    , "") : ""}
  NODE
  ]) : ""}

  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? "## Problematic Deployments\n" : ""}
  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? join("\n", [
    for deployment in local.enhanced_summary.problematic_deployments : <<-DEPLOYMENT
    - Deployment '${deployment.name}' in namespace '${deployment.namespace}':
      - Desired replicas: ${deployment.replicas}
      - Available: ${deployment.available}/${deployment.replicas}
      - Ready: ${deployment.ready}/${deployment.replicas}
      - Health: ${format("%.1f", (deployment.ready / deployment.replicas) * 100)}%
    DEPLOYMENT
  ]) : var.include_deployment_details ? "## Deployments\nAll deployments are healthy with expected number of replicas." : ""}

  ## Analysis Request
  As a Kubernetes expert, please provide an analysis of this cluster:

  1. Health Assessment:
     - Is the cluster meeting its ${var.health_threshold}% health threshold requirement?
     - What is the overall health rating (Healthy/Degraded/Critical)?
     - What are the priority issues that need attention?

  2. Issue Diagnostics:
     - For each problematic pod${var.include_deployment_details ? " and deployment" : ""}, what is the likely root cause?
     - What specific resolution steps would you recommend?
     - What kubectl commands would help diagnose or fix these issues?

  3. Resource Evaluation:
     - Is the cluster appropriately sized for its workload?
     - Are there any potential bottlenecks or resource constraints?
     - How is the workload distributed across the cluster?

  4. Optimization Recommendations:
     - What improvements to the cluster configuration would you suggest?
     - How could resource utilization be optimized?
     - What monitoring or alerting would you recommend?

  Format your response as a structured report with:
  - Executive Summary (1-2 paragraphs on overall status)
  - Critical Issues (prioritized list with diagnostics)
  - Resolution Steps (with specific kubectl commands)
  - Resource Analysis (evaluation of current allocation)
  - Recommendations (3-5 key suggestions for improvement)
  EOT

# Health-focused prompt
  health_prompt = <<-EOT
  # Kubernetes Cluster Health Assessment

  ${local.cluster_context}

  ## Cluster Health Metrics
  - Total pods: ${local.base_summary.total_pods}
  - Running pods: ${local.base_summary.running_pods_count} (${format("%.1f", local.health_percentage)}%)
  - Health threshold: ${var.health_threshold}% 
  - Current status: ${local.is_healthy ? "HEALTHY ✓" : "UNHEALTHY ⚠️"}
  - Problematic pods: ${local.base_summary.problematic_pods_count}
  ${var.include_deployment_details ? "- Problematic deployments: ${length(local.enhanced_summary.problematic_deployments)}" : ""}
  ${var.include_resource_metrics ? "- Pods with high CPU utilization: ${local.enhanced_summary.pods_with_high_cpu}" : ""}
  ${var.include_resource_metrics ? "- Pods with high memory utilization: ${local.enhanced_summary.pods_with_high_memory}" : ""}

  ## Health Status by Namespace
  ${join("\n", [
    for namespace, info in local.namespace_summary : <<-NAMESPACE
    - ${namespace}: ${format("%.1f", info.total_pods > 0 ? (lookup(info.status_counts, "Running", 0) / info.total_pods * 100) : 100)}% healthy (${lookup(info.status_counts, "Running", 0)}/${info.total_pods} pods running)
    NAMESPACE
  ])}

  ## Problematic Resources
  ${length(local.problematic_pods_with_events) > 0 ? "### Problematic Pods\n" : ""}
  ${length(local.problematic_pods_with_events) > 0 ? join("\n", [
    for pod in local.problematic_pods_with_events : <<-POD
    - Pod '${pod.name}' in namespace '${pod.namespace}':
      - Status: ${pod.status}
      - Node: ${pod.node_name}
      - Start Time: ${pod.start_time}
      - Events:
        ${try(length(pod.events) > 0, false) ? join("\n    ", [
          for event in try(pod.events, []) : "- ${event.reason}: ${event.message} (${event.count} times, last occurred at ${event.time})"
      ]) : "      No events found."}
      - Issues:
        ${join("\n        ", [
          for container in pod.containers : "- Container ${container.name}: ${container.ready ? "Ready" : "Not Ready"}"
        ])}
        ${length(pod.conditions) > 0 ? join("\n        ", [
          for condition in pod.conditions : "- Condition ${condition.type}: ${condition.status}"
        ]) : "        - No conditions available"}
        ${var.include_resource_metrics ? try(<<-METRICS
        - Resource Issues:
          ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[pod.containers[0].name].cpu_utilization_vs_limit > 80, false) ? "- High CPU utilization" : ""}
          ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[pod.containers[0].name].memory_utilization_vs_limit > 80, false) ? "- High memory utilization" : ""}
          ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[pod.containers[0].name].cpu_utilization_vs_request < 20, false) ? "- Low CPU efficiency" : ""}
          ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[pod.containers[0].name].memory_utilization_vs_request < 20, false) ? "- Low memory efficiency" : ""}
        METRICS
        , "") : ""}
    POD
  ]) : "No problematic pods found."}

  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? "### Problematic Deployments\n" : ""}
  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? join("\n", [
    for deployment in local.enhanced_summary.problematic_deployments : <<-DEPLOYMENT
    - Deployment '${deployment.name}' in namespace '${deployment.namespace}':
      - Desired replicas: ${deployment.replicas}
      - Available: ${deployment.available}
      - Ready: ${deployment.ready}
      - Health: ${(deployment.ready / deployment.replicas) * 100}%
    DEPLOYMENT
  ]) : ""}

  ## Analysis Request: Health Assessment
  As a Kubernetes health expert, please:

  1. Evaluate the overall health status of this cluster (healthy/degraded/critical)
  2. For each problematic pod or deployment, diagnose the likely root cause
  3. Provide specific remediation steps for each identified issue
  4. Recommend health monitoring improvements based on the observed patterns
  5. Suggest appropriate alert thresholds for this cluster

  Format your response as a structured health report with:
  - Executive Summary (1-2 paragraphs)
  - Critical Issues (prioritized)
  - Remediation Steps (with kubectl commands where applicable)
  - Monitoring Recommendations
  EOT

  # Performance optimization prompt
  performance_prompt = <<-EOT
  # Kubernetes Cluster Performance Analysis

  ${local.cluster_context}

  ## Resource Allocation
  - Total namespaces: ${local.base_summary.namespaces_count}
  - Total pods: ${local.base_summary.total_pods}
  - Pods per namespace: ${local.base_summary.total_pods > 0 ? format("%.1f", local.base_summary.total_pods / local.base_summary.namespaces_count) : 0} (average)
  ${var.include_node_info ? "- Total nodes: ${length(local.nodes)}" : ""}
  ${var.include_node_info ? "- Pods per node: ${local.base_summary.total_pods > 0 && length(local.nodes) > 0 ? format("%.1f", local.base_summary.total_pods / length(local.nodes)) : 0} (average)" : ""}

  ## Namespace Distribution
  ${join("\n", [for namespace, count in local.base_summary.pods_by_namespace_count : "- ${namespace}: ${count} pods"])}

  ${var.include_node_info ? "## Node Resources\n" : ""}
  ${var.include_node_info ? join("\n", [for node in local.nodes : <<-NODE
  - Node '${node.name}':
    - CPU: ${try(node.capacity.cpu, "Unknown")}
    - Memory: ${try(node.capacity.memory, "Unknown")}
    - Pods: ${length([for pod in local.all_pods : pod if pod.node_name == node.name])}
    ${var.include_resource_metrics ? try(<<-METRICS
    - Current Usage:
      - CPU: ${try(local.node_metrics[node.name].cpu, "No metrics")}
      - Memory: ${try(local.node_metrics[node.name].memory, "No metrics")}
    METRICS
    , "") : ""}
  NODE
  ]) : ""}

  ${var.include_deployment_details ? "## Deployment Configuration\n" : ""}
  ${var.include_deployment_details ? join("\n", [for key, deployment in local.enhanced_summary.deployments : <<-DEPLOYMENT
  - Deployment '${split("/", key)[1]}' in namespace '${split("/", key)[0]}':
    - Replicas: ${deployment.replicas}
    - Ready: ${deployment.ready_replicas}/${deployment.replicas} (${deployment.health_percent}%)
  DEPLOYMENT
  ]) : ""}

  ${var.include_resource_metrics ? <<-RESOURCE_METRICS
  ## Resource Metrics by Namespace
  ${join("\n", [for namespace in sort(distinct([for key, pod in local.pod_metrics : pod.namespace])) : 
    !contains(var.ignore_namespaces, namespace) ?
    <<-NAMESPACE
  - Namespace '${namespace}':
    - Pods with metrics: ${length([for key, pod in local.pod_metrics : pod if pod.namespace == namespace])}
    - Pod metrics data:
  ${join("\n", [for key, pod in local.pod_metrics : 
    pod.namespace == namespace ?
    <<-POD
      - Pod: ${pod.name}
        - Containers:
  ${join("\n", [for container_name, container in pod.containers :
    <<-CONTAINER
          - ${container_name}:
            - Current CPU: ${container.cpu}
            - Current Memory: ${container.memory}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_request != null, false) ? 
    "          - CPU Request: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_request}" : ""}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_request != null, false) ? 
    "          - Memory Request: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_request}" : ""}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_limit != null, false) ? 
    "          - CPU Limit: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_limit}" : ""}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_limit != null, false) ? 
    "          - Memory Limit: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_limit}" : ""}
    CONTAINER
  ])}
    POD
    : ""
  ])}
    NAMESPACE
    : ""
  ])}
  RESOURCE_METRICS
  : ""}

  ## Analysis Request: Performance Analysis
  As a Kubernetes performance expert, please:

  1. Evaluate the current performance configuration of this cluster
  2. Identify potential bottlenecks or performance constraints
  3. Suggest resource optimization strategies for improved performance
  4. Recommend scaling considerations (horizontal vs. vertical)
  5. Provide best practices for performance monitoring

  Format your response as a performance optimization report with:
  - Overall Performance Assessment
  - Bottleneck Identification
  - Optimization Recommendations
  - Scaling Strategy
  - Monitoring Recommendations
  EOT

  # Security assessment prompt
  security_prompt = <<-EOT
  # Kubernetes Cluster Security Assessment

  ${local.cluster_context}

  ## Namespace Configuration
  - Total namespaces: ${local.base_summary.namespaces_count}
  - Namespaces: ${join(", ", local.filtered_namespaces)}
  - Ignored system namespaces: ${join(", ", var.ignore_namespaces)}

  ## Workload Distribution
  ${join("\n", [
    for namespace, info in local.namespace_summary : <<-NAMESPACE
  - Namespace '${namespace}': ${info.total_pods} pods
    Pod names: ${join(", ", info.pod_names)}
  NAMESPACE
  ])}

  ## Container Image Analysis
  ${join("\n", [
    for namespace, pods in local.pods_by_namespace : <<-NAMESPACE
  - Namespace '${namespace}' container images:
  ${join("\n", distinct(flatten([
    for pod in pods : [
      for container in pod.containers : "  - ${container.image}"
    ]
  ])))}
  NAMESPACE
  ])}

  ## Analysis Request: Security Assessment
  As a Kubernetes security expert, please:

  1. Assess the namespace isolation strategy based on the observed workload
  2. Evaluate the container image usage for potential security risks
  3. Identify deviations from Kubernetes security best practices
  4. Recommend namespace-level security policies appropriate for this cluster
  5. Suggest image security and scanning strategies based on the observed patterns
  6. Provide guidance on implementing network policies for proper workload isolation

  Format your response as a security assessment report with:
  - Security Rating (Low/Medium/High risk with explanation)
  - Critical Security Findings
  - Security Recommendations (prioritized by impact)
  - Network Policy Guidelines
  - Best Practice Implementation Steps
  EOT

  # Troubleshooting prompt
  troubleshooting_prompt = <<-EOT
  # Kubernetes Cluster Troubleshooting Guide
  
  ${local.cluster_context}
  
  ## Cluster Health Status
  - Total pods: ${local.base_summary.total_pods}
  - Running pods: ${local.base_summary.running_pods_count} (${format("%.1f", local.health_percentage)}%)
  - Health threshold: ${var.health_threshold}% 
  - Current status: ${local.is_healthy ? "HEALTHY ✓" : "UNHEALTHY ⚠️"}
  - Problematic pods: ${local.base_summary.problematic_pods_count}
  ${var.include_deployment_details ? "- Problematic deployments: ${length(local.enhanced_summary.problematic_deployments)}" : ""}
  ${var.include_resource_metrics ? "- Pods with high CPU utilization: ${local.enhanced_summary.pods_with_high_cpu}" : ""}
  ${var.include_resource_metrics ? "- Pods with high memory utilization: ${local.enhanced_summary.pods_with_high_memory}" : ""}
  
  ## Problematic Resources
  ${length(local.problematic_pods_with_events) > 0 ? "### Problematic Pods\n" : ""}
  ${length(local.problematic_pods_with_events) > 0 ? join("\n", [
    for pod in local.problematic_pods_with_events : <<-POD
  - Pod '${pod.name}' in namespace '${pod.namespace}':
    - Status: ${pod.status}
    - Node: ${pod.node_name}
    - Pod IP: ${pod.pod_ip}
    - Start Time: ${pod.start_time}
    - Events:
        ${try(length(pod.events) > 0, false) ? join("\n    ", [
          for event in try(pod.events, []) : "- ${event.reason}: ${event.message} (${event.count} times, last occurred at ${event.time})"
      ]) : "      No events found."}
    - Containers:
      ${join("\n    ", [
        for container in pod.containers : "- ${container.name} (${container.image}): ${container.ready ? "Ready" : "Not Ready"}"
      ])}
    - Conditions:
      ${length(pod.conditions) > 0 ? join("\n    ", [
        for condition in pod.conditions : "- ${condition.type}: ${condition.status}"
      ]) : "    - No conditions available"}
    ${var.include_resource_metrics ? <<-METRICS
    - Resource Information:
  ${join("\n", [
    for container in pod.containers : <<-CONTAINER
        - Container ${container.name}:
          - CPU Request: ${try(container.resources.requests.cpu, "None")}
          - Memory Request: ${try(container.resources.requests.memory, "None")}
          - CPU Limit: ${try(container.resources.limits.cpu, "None")}
          - Memory Limit: ${try(container.resources.limits.memory, "None")}
          - CPU Usage: ${try(local.pod_metrics["${pod.namespace}/${pod.name}"].containers[container.name].cpu, "No metrics")}
          - Memory Usage: ${try(local.pod_metrics["${pod.namespace}/${pod.name}"].containers[container.name].memory, "No metrics")}
    CONTAINER
  ])}
    METRICS
    : ""}
  POD
  ]) : "No problematic pods found."}
  
  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? "### Problematic Deployments\n" : ""}
  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? join("\n", [
    for deployment in local.enhanced_summary.problematic_deployments : <<-DEPLOYMENT
  - Deployment '${deployment.name}' in namespace '${deployment.namespace}':
    - Desired replicas: ${deployment.replicas}
    - Available: ${deployment.available}
    - Ready: ${deployment.ready}
    - Health: ${(deployment.ready / deployment.replicas) * 100}%
    - Issue: ${deployment.reason}
  DEPLOYMENT
  ]) : ""}
  
  ## Analysis Request: Troubleshooting Guide
  As a Kubernetes troubleshooting expert, please:
  
  1. Diagnose each problematic pod with detailed explanation of the likely issues
  2. Provide step-by-step troubleshooting commands (exact kubectl commands) for each problem
  3. Suggest specific configuration changes to resolve the identified issues
  4. Explain how to verify the fixes have been properly applied
  5. Recommend proactive monitoring to prevent similar issues in the future
  
  Format your response as a practical troubleshooting guide with:
  - Issue Summary
  - Diagnostic Commands (kubectl commands that would help diagnose each issue)
  - Resolution Steps (step-by-step with exact commands or YAML snippets)
  - Verification Procedures
  - Prevention Recommendations
  EOT
    
  # Comprehensive analysis prompt
  comprehensive_prompt = <<-EOT
  # Comprehensive Kubernetes Cluster Analysis
  
  ${local.cluster_context}
  
  ## Cluster Overview
  - Total pods: ${local.base_summary.total_pods}
  - Total namespaces (after filtering): ${local.base_summary.namespaces_count}
  - Ignored namespaces: ${join(", ", var.ignore_namespaces)}
  - Running pods: ${local.base_summary.running_pods_count}
  - Problematic pods: ${local.base_summary.problematic_pods_count}
  - Health percentage: ${format("%.1f", local.health_percentage)}% (threshold: ${var.health_threshold}%)
  - Overall status: ${local.is_healthy ? "HEALTHY ✓" : "UNHEALTHY ⚠️"}
  ${var.include_node_info ? "- Total nodes: ${length(local.nodes)}" : ""}
  ${var.include_deployment_details ? "- Total deployments: ${length(local.all_deployments)}" : ""}
  ${var.include_deployment_details ? "- Problematic deployments: ${length(local.enhanced_summary.problematic_deployments)}" : ""}
  ${var.include_resource_metrics ? "- Pods with resource metrics: ${length(local.pod_metrics)}" : ""}
  ${var.include_resource_metrics ? "- Pods with high CPU utilization: ${local.enhanced_summary.pods_with_high_cpu}" : ""}
  ${var.include_resource_metrics ? "- Pods with high memory utilization: ${local.enhanced_summary.pods_with_high_memory}" : ""}
  
  ## Pods by Status
  ${join("\n", [for status, info in local.status_summary : "- ${status}: ${info.total_pods} pods (${join(", ", info.pod_names)})"])}
  
  ## Pods by Namespace
  ${join("\n", [for namespace, info in local.namespace_summary : "- ${namespace}: ${info.total_pods} pods (${join(", ", info.pod_names)})"])}
  
  ## Problematic Resources
  ${length(local.problematic_pods_with_events) > 0 ? "### Problematic Pods\n" : ""}
  ${length(local.problematic_pods_with_events) > 0 ? join("\n", [
    for pod in local.problematic_pods_with_events : <<-POD
  - Pod '${pod.name}' in namespace '${pod.namespace}':
    - Status: ${pod.status}
    - Node: ${pod.node_name}
    - Pod IP: ${pod.pod_ip}
    - Start Time: ${pod.start_time}
    - Events:
        ${try(length(pod.events) > 0, false) ? join("\n    ", [
          for event in try(pod.events, []) : "- ${event.reason}: ${event.message} (${event.count} times, last occurred at ${event.time})"
      ]) : "      No events found."}
    - Containers:
      ${join("\n    ", [
        for container in pod.containers : "- ${container.name} (${container.image}): ${container.ready ? "Ready" : "Not Ready"}"
      ])}
    - Conditions:
      ${length(pod.conditions) > 0 ? join("\n    ", [
        for condition in pod.conditions : "- ${condition.type}: ${condition.status}"
      ]) : "    - No conditions available"}
    ${var.include_resource_metrics ? <<-METRICS
    - Resource Information:
  ${join("\n", [
    for container in pod.containers : <<-CONTAINER
        - Container ${container.name}:
          - CPU Request: ${try(container.resources.requests.cpu, "None")}
          - Memory Request: ${try(container.resources.requests.memory, "None")}
          - CPU Limit: ${try(container.resources.limits.cpu, "None")}
          - Memory Limit: ${try(container.resources.limits.memory, "None")}
          - CPU Usage: ${try(local.pod_metrics["${pod.namespace}/${pod.name}"].containers[container.name].cpu, "No metrics")}
          - Memory Usage: ${try(local.pod_metrics["${pod.namespace}/${pod.name}"].containers[container.name].memory, "No metrics")}
    CONTAINER
  ])}
    METRICS
    : ""}
  POD
  ]) : "No problematic pods found."}
  
  ${var.include_node_info ? "## Node Information\n" : ""}
  ${var.include_node_info ? join("\n", [for node in local.nodes : "- Node '${node.name}' running kubelet ${node.kubelet_version}. Ready: ${try(node.conditions[index(node.conditions.*.type, "Ready")].status, "Unknown")}, Memory: ${try(node.capacity.memory, "Unknown")}, CPU: ${try(node.capacity.cpu, "Unknown")}"]) : ""}
  
  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? "## Problematic Deployments\n" : ""}
  ${var.include_deployment_details && length(local.enhanced_summary.problematic_deployments) > 0 ? join("\n", [
    for deployment in local.enhanced_summary.problematic_deployments : <<-DEPLOYMENT
  - Deployment '${deployment.name}' in namespace '${deployment.namespace}':
    - Replicas: ${deployment.replicas}
    - Available: ${deployment.available}
    - Ready: ${deployment.ready}
    - Health %: ${(deployment.ready / deployment.replicas) * 100}%
    - Issue: ${deployment.reason}
  DEPLOYMENT
  ]) : ""}
  
  ${var.include_resource_metrics ? <<-RESOURCE_ANALYSIS
  ## Resource Utilization Analysis
  
  ### Resource Configuration Summary
  - Pods with resource requests: ${length([for pod in local.all_pods : pod if try(length([for container in pod.containers : container if try(container.resources.requests != null, false)]) > 0, false)])}
  - Pods with resource limits: ${length([for pod in local.all_pods : pod if try(length([for container in pod.containers : container if try(container.resources.limits != null, false)]) > 0, false)])}
  - Pods without resource requests: ${local.base_summary.total_pods - length([for pod in local.all_pods : pod if try(length([for container in pod.containers : container if try(container.resources.requests != null, false)]) > 0, false)])}
  - Pods without resource limits: ${local.base_summary.total_pods - length([for pod in local.all_pods : pod if try(length([for container in pod.containers : container if try(container.resources.limits != null, false)]) > 0, false)])}
  
  ### Resource Efficiency by Namespace
  ${join("\n", [for namespace in sort(distinct([for key, pod in local.pod_metrics : pod.namespace])) : 
    !contains(var.ignore_namespaces, namespace) ?
    <<-NAMESPACE
  - Namespace '${namespace}':
    - Pods with metrics: ${length([for key, pod in local.pod_metrics : pod if pod.namespace == namespace])}
    - Pod metrics data:
  ${join("\n", [for key, pod in local.pod_metrics : 
    pod.namespace == namespace ?
    <<-POD
      - Pod: ${pod.name}
        - Containers:
  ${join("\n", [for container_name, container in pod.containers :
    <<-CONTAINER
          - ${container_name}:
            - Current CPU: ${container.cpu}
            - Current Memory: ${container.memory}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_request != null, false) ? 
    "          - CPU Request: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_request}" : ""}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_request != null, false) ? 
    "          - Memory Request: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_request}" : ""}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_limit != null, false) ? 
    "          - CPU Limit: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_limit}" : ""}
  ${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_limit != null, false) ? 
    "          - Memory Limit: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_limit}" : ""}
    CONTAINER
  ])}
    POD
    : ""
  ])}
    NAMESPACE
    : ""
  ])}
  RESOURCE_ANALYSIS
  : "Resource metrics collection not enabled. Enable 'include_resource_metrics' for detailed resource analysis."}
  
  ## Analysis Request: Comprehensive Evaluation
  As a Kubernetes expert, please provide a comprehensive analysis that includes:
  
  1. **Health Assessment**:
     - Evaluate the overall health status of this cluster
     - Diagnose each problematic pod or deployment
     - Recommend specific remediation steps
  
  2. **Performance Optimization**:
     - Identify potential bottlenecks or resource constraints
     - Suggest resource allocation improvements
     - Recommend scaling strategies
  
  3. **Security Evaluation**:
     - Assess namespace isolation and workload distribution
     - Recommend security best practices based on the observed configuration
     - Suggest network policies appropriate for this setup
  
  4. **Operational Recommendations**:
     - Provide monitoring recommendations
     - Suggest backup and disaster recovery approaches
     - Recommend maintenance procedures
  
  Format your response as a comprehensive report with clearly delineated sections for each analysis area. Include practical, actionable recommendations with specific commands or configuration examples where appropriate.
  EOT
  
  # Resource optimization prompt
  resource_optimization_prompt = <<-EOT
  # Kubernetes Cluster Resource Optimization Analysis

  ${local.cluster_context}

  ## Resource Configuration Summary
  - Total pods: ${local.base_summary.total_pods}
  - Pods with resource requests: ${length([for pod in local.all_pods : pod if try(length([for container in pod.containers : container if try(container.resources.requests != null, false)]) > 0, false)])}
  - Pods with resource limits: ${length([for pod in local.all_pods : pod if try(length([for container in pod.containers : container if try(container.resources.limits != null, false)]) > 0, false)])}
  ${var.include_resource_metrics ? "- Pods with metrics available: ${length(local.pod_metrics)}" : ""}
  ${var.include_node_info ? "- Total nodes: ${length(local.nodes)}" : ""}
  ${var.include_node_info ? "- Total cluster CPU capacity: ${sum([for node in local.nodes : try(tonumber(replace(node.capacity.cpu, "m", "")), 0)])}m" : ""}
  ${var.include_node_info ? "- Total cluster memory capacity: ${sum([for node in local.nodes : try(tonumber(replace(node.capacity.memory, "Ki", "")), 0)])}Ki" : ""}

  ## Resource Utilization Concerns
  ${var.include_resource_metrics ? <<-CONCERNS
  ### High CPU Utilization (>80% of limit)
  ${length([for pod_key, pod_data in local.pod_resource_utilization : pod_data if try(
  length([for container_name, container in pod_data.containers : container_name if 
    try(container.cpu_utilization_vs_limit > 80, false)
  ]) > 0, false)]) > 0 ? 
  join("\n", [for pod_key, pod_data in {
    for key, data in local.pod_resource_utilization : key => data if try(
      length([for container_name, container in data.containers : container_name if 
        try(container.cpu_utilization_vs_limit > 80, false)
      ]) > 0,
      false
    ) && contains(local.filtered_namespaces, data.namespace)
  } : <<-POD
  - Pod '${pod_data.name}' in namespace '${pod_data.namespace}':
    ${join("\n    ", [for container_name, container in pod_data.containers : <<-CONTAINER
    - Container '${container_name}':
      - CPU: ${format("%.1f", container.cpu_utilization_vs_limit)}% of limit
      - Current: ${container.cpu_usage}
      - Limit: ${container.cpu_limit}
    CONTAINER
    if try(container.cpu_utilization_vs_limit > 80, false)])}
  POD
  ]) : "No pods currently exceed 80% of their CPU limit."
}

  ### High Memory Utilization (>80% of limit)
  ${length([for pod_key, pod_data in local.pod_resource_utilization : pod_data if try(
  length([for container_name, container in pod_data.containers : container_name if 
    try(container.memory_utilization_vs_limit > 80, false)
  ]) > 0, false)]) > 0 ? 
  join("\n", [for pod_key, pod_data in {
    for key, data in local.pod_resource_utilization : key => data if try(
      length([for container_name, container in data.containers : container_name if 
        try(container.memory_utilization_vs_limit > 80, false)
      ]) > 0,
      false
    ) && contains(local.filtered_namespaces, data.namespace)
  } : <<-POD
  - Pod '${pod_data.name}' in namespace '${pod_data.namespace}':
    ${join("\n    ", [for container_name, container in pod_data.containers : <<-CONTAINER
    - Container '${container_name}':
      - Memory: ${format("%.1f", container.memory_utilization_vs_limit)}% of limit
      - Current: ${container.memory_usage}
      - Limit: ${container.memory_limit}
    CONTAINER
    if try(container.memory_utilization_vs_limit > 80, false)])}
  POD
  ]) : "No pods currently exceed 80% of their memory limit."
}

  ### Low CPU Utilization (<20% of request)
  ${length([for pod_key, pod_data in local.pod_resource_utilization : pod_data if try(
  length([for container_name, container in pod_data.containers : container_name if 
    try(container.cpu_utilization_vs_request < 20 && container.cpu_utilization_vs_request != null, false)
  ]) > 0, false)]) > 0 ? 
  join("\n", [for pod_key, pod_data in {
    for key, data in local.pod_resource_utilization : key => data if try(
      length([for container_name, container in data.containers : container_name if 
        try(container.cpu_utilization_vs_request < 20 && container.cpu_utilization_vs_request != null, false)
      ]) > 0,
      false
    ) && contains(local.filtered_namespaces, data.namespace)
  } : <<-POD
  - Pod '${pod_data.name}' in namespace '${pod_data.namespace}':
    ${join("\n    ", [for container_name, container in pod_data.containers : <<-CONTAINER
    - Container '${container_name}':
      - CPU: ${format("%.1f", container.cpu_utilization_vs_request)}% of request
      - Current: ${container.cpu_usage}
      - Request: ${container.cpu_request}
    CONTAINER
    if try(container.cpu_utilization_vs_request < 20 && container.cpu_utilization_vs_request != null, false)])}
  POD
  ]) : "No pods currently use less than 20% of their CPU request (potentially over-provisioned)."
  }

  ### Low Memory Utilization (<20% of request)
  ${length([for pod_key, pod_data in local.pod_resource_utilization : pod_data if try(
  length([for container_name, container in pod_data.containers : container_name if 
    try(container.memory_utilization_vs_request < 20 && container.memory_utilization_vs_request != null, false)
  ]) > 0, false)]) > 0 ? 
  join("\n", [for pod_key, pod_data in {
    for key, data in local.pod_resource_utilization : key => data if try(
      length([for container_name, container in data.containers : container_name if 
        try(container.memory_utilization_vs_request < 20 && container.memory_utilization_vs_request != null, false)
      ]) > 0,
      false
    ) && contains(local.filtered_namespaces, data.namespace)
  } : <<-POD
  - Pod '${pod_data.name}' in namespace '${pod_data.namespace}':
    ${join("\n    ", [for container_name, container in pod_data.containers : <<-CONTAINER
    - Container '${container_name}':
      - Memory: ${format("%.1f", container.memory_utilization_vs_request)}% of request
      - Current: ${container.memory_usage}
      - Request: ${container.memory_request}
    CONTAINER
    if try(container.memory_utilization_vs_request < 20 && container.memory_utilization_vs_request != null, false)])}
  POD
  ]) : "No pods currently use less than 20% of their memory request (potentially over-provisioned)."
  }
  CONCERNS
  : "Resource metrics collection not enabled. Enable 'include_resource_metrics' for detailed resource analysis."}

  ## Resource Efficiency by Namespace
${var.include_resource_metrics ? 
  join("\n", [for namespace in sort(distinct([for key, pod in local.pod_metrics : pod.namespace])) : 
    !contains(var.ignore_namespaces, namespace) ?
    <<-NAMESPACE
- Namespace '${namespace}':
  - Pods with metrics: ${length([for key, pod in local.pod_metrics : pod if pod.namespace == namespace])}
  - Pod metrics data:
${join("\n", [for key, pod in local.pod_metrics : 
  pod.namespace == namespace ?
  <<-POD
    - Pod: ${pod.name}
      - Containers:
${join("\n", [for container_name, container in pod.containers :
  <<-CONTAINER
        - ${container_name}:
          - Current CPU: ${container.cpu}
          - Current Memory: ${container.memory}
${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_request != null, false) ? 
  "          - CPU Request: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_request}" : ""}
${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_request != null, false) ? 
  "          - Memory Request: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_request}" : ""}
${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_limit != null, false) ? 
  "          - CPU Limit: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].cpu_limit}" : ""}
${try(local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_limit != null, false) ? 
  "          - Memory Limit: ${local.pod_resource_utilization["${pod.namespace}/${pod.name}"].containers[container_name].memory_limit}" : ""}
  CONTAINER
])}
  POD
  : ""
])}
  NAMESPACE
  : ""
])
: "Resource metrics collection not enabled. Enable 'include_resource_metrics' for namespace efficiency analysis."
}

  ## Analysis Request: Resource Optimization
  As a Kubernetes resource optimization expert, please:

  1. Analyze the resource allocation efficiency of this cluster based on the data provided
  2. Identify containers that are over-provisioned or under-provisioned
  3. Recommend specific adjustments to resource requests and limits for each problematic container
  4. Suggest best practices for resource allocation in this specific environment
  5. Provide a cost optimization strategy based on the observed resource usage patterns

  Format your response as a detailed resource optimization report with:
  - Executive Summary of resource efficiency
  - Critical Resource Misconfigurations (prioritized by impact)
  - Specific Recommendations (with exact resource values where possible)
  - Implementation Plan for resource optimization
  - Monitoring Strategy to validate changes
  EOT

  # Capacity planning prompt
  capacity_planning_prompt = <<-EOT
  # Kubernetes Cluster Capacity Planning Analysis

  ${local.cluster_context}

  ## Current Cluster Capacity
  ${var.include_node_info ? <<-NODES
  - Total Nodes: ${length(local.nodes)}
  - Total CPU Capacity: ${sum([for node in local.nodes : try(tonumber(replace(node.capacity.cpu, "m", "")), 0)])}m
  - Total Memory Capacity: ${sum([for node in local.nodes : try(tonumber(replace(node.capacity.memory, "Ki", "")), 0)])}Ki
  NODES
  : "Node information not available. Enable 'include_node_info' for capacity details."}

  ## Current Resource Allocation - User Namespaces Only
  - Total Pods: ${length([for pod in local.all_pods : pod if contains(local.filtered_namespaces, pod.namespace)])}
  - Total CPU Requested: ${sum([for pod in local.all_pods : sum([for container in pod.containers : try(tonumber(replace(container.resources.requests.cpu, "m", "")), 0)]) if contains(local.filtered_namespaces, pod.namespace)])}m
  - Total Memory Requested: ${sum([for pod in local.all_pods : sum([for container in pod.containers : try(tonumber(replace(container.resources.requests.memory, "Mi", "")), 0)]) if contains(local.filtered_namespaces, pod.namespace)])}Mi

  ## Resource Allocation by Namespace
  ${join("\n", [for namespace, pods in {
    for pod in local.all_pods : pod.namespace => pod... if contains(local.filtered_namespaces, pod.namespace)
  } : <<-NAMESPACE
  - Namespace '${namespace}':
    - Pods: ${length(pods)}
    - CPU Requested: ${sum([for pod in pods : sum([for container in pod.containers : try(tonumber(replace(container.resources.requests.cpu, "m", "")), 0)])])}m
    - Memory Requested: ${sum([for pod in pods : sum([for container in pod.containers : try(tonumber(replace(container.resources.requests.memory, "Mi", "")), 0)])])}Mi
  NAMESPACE
  ])}

  ${var.include_resource_metrics ? <<-METRICS
## Current Resource Utilization - User Namespaces Only
${length(local.pod_metrics) > 0 ? "- Pods with metrics: ${length(local.pod_metrics)}" : "- No metrics data available"}

### Pod Resource Metrics by Namespace
${join("\n", [for namespace in sort(distinct([for key, pod in local.pod_metrics : pod.namespace])) : 
  !contains(var.ignore_namespaces, namespace) ?
  <<-NAMESPACE
- Namespace '${namespace}':
  - Pods with metrics: ${length([for key, pod in local.pod_metrics : pod if pod.namespace == namespace])}
  - CPU and Memory Usage:
    ${join("\n    ", [for key, pod in local.pod_metrics : 
      pod.namespace == namespace ?
      "${pod.name}: ${join(", ", [for container_name, container in pod.containers : 
        "${container_name} (CPU: ${container.cpu}, Memory: ${container.memory})"
      ])}"
      : ""
    ])}
  NAMESPACE
  : ""
])}
METRICS
: "Resource metrics collection not enabled. Enable 'include_resource_metrics' for utilization details."}

  ## Analysis Request: Capacity Planning
  As a Kubernetes capacity planning expert, please:

  1. Evaluate the current cluster resource utilization and efficiency
  2. Project future capacity needs based on current usage patterns
  3. Identify potential bottlenecks that might limit scalability
  4. Recommend a capacity planning strategy for this cluster
  5. Suggest appropriate resource allocation guidelines for the observed workload types
  6. Provide scaling recommendations (horizontal vs vertical) for different workload types

  Format your response as a comprehensive capacity planning report with:
  - Current Capacity Assessment
  - Utilization Efficiency Analysis
  - Scalability Considerations
  - Growth Projections and Recommendations
  - Implementation Roadmap
  EOT

  ## Select the appropriate prompt based on analysis_type
  selected_ai_prompt = {
    "standard"       = (var.include_node_info || var.include_deployment_details) ? local.enhanced_ai_prompt : local.ai_prompt,
    "health"         = local.health_prompt,
    "performance"    = local.performance_prompt,
    "security"       = local.security_prompt,
    "troubleshooting" = local.troubleshooting_prompt,
    "comprehensive"  = local.comprehensive_prompt,
    "resource"       = local.resource_optimization_prompt,
    "capacity"       = local.capacity_planning_prompt
  }[var.analysis_type]
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
    problematic_pods_count = local.base_summary.problematic_pods_count,
    problematic_pods_summary = {
      for pod in local.problematic_pods_with_events : pod.name => {
        namespace = pod.namespace,
        status = pod.status,
        likely_cause = length(pod.events) > 0 ? pod.events[0].reason : "Unknown",
        event_count = length(pod.events)
      }
    }
  })
  filename   = "${var.output_path}/health_status.json"
}

resource "local_file" "root_cause_analysis" {
  depends_on = [local_file.ensure_output_dir, data.kubernetes_resources.pod_events]
  content    = jsonencode({
    timestamp = timestamp(),
    analysis_date = formatdate("YYYY-MM-DD hh:mm:ss", timestamp()),
    problematic_resources = {
      pods = {
        for pod in local.problematic_pods_with_events : pod.name => {
          namespace = pod.namespace,
          status = pod.status,
          node = pod.node_name,
          containers = [for container in pod.containers : {
            name = container.name,
            image = container.image,
            ready = container.ready
          }],
          events = pod.events,
          diagnostic = {
            likely_cause = length(pod.events) > 0 ? pod.events[0].reason : pod.status == "Pending" ? "Scheduling or Resource Issue" : pod.status == "Failed" ? "Container Error" : "Unknown",
            suggested_action = length(pod.events) > 0 ? (
              contains(["ImagePullBackOff", "ErrImagePull"], pod.events[0].reason) ? "Check container image name and ensure it exists" :
              contains(["CrashLoopBackOff"], pod.events[0].reason) ? "Investigate container logs for application errors" :
              contains(["Unhealthy"], pod.events[0].reason) ? "Check probe configuration and application health" :
              "Investigate cluster events and logs"
            ) : "Check pod specification and cluster capacity"
          }
        }
      }
    }
  })
  filename   = "${var.output_path}/root_cause_analysis.json"
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

# Output detailed data for any problematic pods with event information
resource "local_file" "problematic_pods" {
  depends_on = [local_file.ensure_output_dir, data.kubernetes_resources.pod_events]
  content    = jsonencode(local.problematic_pods_with_events)
  filename   = "${var.output_path}/problematic_pods.json"
}

# Generate optional node data output files
resource "local_file" "node_data" {
  count      = var.include_node_info ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.nodes)
  filename   = "${var.output_path}/node_data.json"
}

# Generate optional deployment data output files
resource "local_file" "deployment_data" {
  count      = var.include_deployment_details ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.all_deployments)
  filename   = "${var.output_path}/deployment_data.json"
}

# Generate resource metrics output files
resource "local_file" "pod_metrics" {
  count      = var.include_resource_metrics ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.pod_metrics)
  filename   = "${var.output_path}/pod_metrics.json"
}

# Generate processed pod metrics output files
resource "local_file" "processed_pod_metrics" {
  count      = var.include_resource_metrics ? 1 : 0
  depends_on = [data.local_file.raw_pod_metrics]
  content    = jsonencode({
    timestamp = timestamp(),
    metrics_count = length(local.pod_metrics),
    pod_metrics = local.pod_metrics,
    filtered_namespaces = var.ignore_namespaces
  })
  filename   = "${var.output_path}/processed_pod_metrics.json"
}

# Generate node metrics output files
resource "local_file" "node_metrics" {
  count      = var.include_resource_metrics && var.include_node_info ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode(local.node_metrics)
  filename   = "${var.output_path}/node_metrics.json"
}

# Generate AI prompt
resource "local_file" "ai_prompt" {
  depends_on = [local_file.ensure_output_dir]
  content    = local.selected_ai_prompt
  filename   = "${var.output_path}/ai_prompt.md"
}

#-----------------------------------------------------------------------------
# DEBUG FILE GENERATION (debug_mode must be set to true in root)
#-----------------------------------------------------------------------------

# DEBUG LOGIC TO DETERMINE IF POD METRICS ARE AVAILABLE OR PROVIDER ISSUE - REMOVE BEFORE PRODUCTION
resource "local_file" "pod_metrics_raw_debug" {
  count      = var.include_resource_metrics && var.debug_mode ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode({
    pod_metrics_objects_available = try(length(data.local_file.raw_pod_metrics[0]) > 0, false),
    pod_metrics_objects_count = try(length(data.local_file.raw_pod_metrics[0]), 0),
    raw_objects = try(data.local_file.raw_pod_metrics[0], []),
    filtered_namespaces = var.ignore_namespaces,
    timestamp = timestamp(),
    note = "This file shows the raw data from the metrics API to help diagnose why pod metrics might not be collected"
  })
  filename   = "${var.output_path}/pod_metrics_raw_debug.json"
}

# Use kubectl directly to verify metrics API is working
resource "null_resource" "kubectl_metrics_check" {
  count = var.include_resource_metrics && var.debug_mode ? 1 : 0
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Running kubectl checks for metrics API..."
      echo "API service status:" > ${var.output_path}/metrics_api_check.txt
      kubectl get apiservice v1beta1.metrics.k8s.io >> ${var.output_path}/metrics_api_check.txt
      echo "\nPod metrics from kubectl:" >> ${var.output_path}/metrics_api_check.txt
      kubectl top pods --all-namespaces >> ${var.output_path}/metrics_api_check.txt || echo "No metrics available via kubectl" >> ${var.output_path}/metrics_api_check.txt
      echo "\nRaw metrics API output:" >> ${var.output_path}/metrics_api_check.txt
      kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods >> ${var.output_path}/metrics_api_check.txt || echo "Failed to get raw metrics" >> ${var.output_path}/metrics_api_check.txt
    EOT
  }
}

# Output pod metrics structure to help diagnose why pod metrics might not be collected
resource "local_file" "debug_pod_structure" {
  count      = var.include_resource_metrics && var.debug_mode ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode({
    metrics_structure = {
      pod_metrics_sample = length(local.pod_metrics) > 0 ? [
        for key, pod in local.pod_metrics : {
          key = key,
          namespace = pod.namespace,
          name = pod.name,
          containers = pod.containers,
          container_names = keys(pod.containers)
        }
      ][0] : null
    },
    pods_structure = {
      pod_sample = length(local.all_pods) > 0 ? [
        for pod in local.all_pods : {
          name = pod.name,
          namespace = pod.namespace,
          status = pod.status,
          container_example = length(pod.containers) > 0 ? pod.containers[0] : null
        }
      ][0] : null
    }
  })
  filename   = "${var.output_path}/debug_data_structure.json"
}

# Output pod resource utilization data to help diagnose why pod metrics might not be collected
resource "local_file" "pod_resource_data" {
  count      = var.include_resource_metrics && var.debug_mode ? 1 : 0
  depends_on = [local_file.ensure_output_dir]
  content    = jsonencode({
    timestamp = timestamp(),
    pod_resource_utilization = local.pod_resource_utilization
  })
  filename   = "${var.output_path}/pod_resource_data.json"
}
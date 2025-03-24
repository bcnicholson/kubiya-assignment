# terraform.tfvars
# Configuration file for the Kubernetes Cluster Analyzer module
# Edit this file to customize the analysis parameters

#-----------------------------------------------------------------------------
# CORE CONFIGURATION VARIABLES
#-----------------------------------------------------------------------------
# These settings control the basic connection to your Kubernetes cluster
# and where output files will be stored

# Path to your Kubernetes configuration file (usually in ~/.kube/config)
config_path = "~/.kube/config"

# The context within your kubeconfig to use (e.g., minikube, docker-desktop, etc.)
config_context = "minikube"

# Directory where all analysis files will be saved (will be created if it doesn't exist)
output_path = "./cluster-analysis"

#-----------------------------------------------------------------------------
# ANALYSIS CONFIGURATION OPTIONS
#-----------------------------------------------------------------------------
# These settings control which components to analyze and how strict the
# health threshold should be

# Enable collection of pod/node resource metrics (requires metrics-server to be installed)
# Set to true for detailed resource utilization analysis (default is false)
include_resource_metrics = true

# Enable detailed node information collection and analysis
# Set to true to include information about all nodes in the cluster (default is false)
include_node_info = true

# Enable detailed deployment analysis
# Set to true to analyze replica counts, update strategies, and deployment health
include_deployment_details = true

# Percentage of pods that must be running for the cluster to be considered healthy
# Higher values enforce stricter health standards (90% is recommended minimum and default)
health_threshold = 90

# Namespaces to exclude from the analysis (default excludes Kubernetes system namespaces)
# To analyze ALL namespaces (including system namespaces), use empty list: []
ignore_namespaces = ["kube-system", "kube-public", "kube-node-lease"]
# ignore_namespaces = [] # Uncomment to include all namespaces (comment line above if using this)

#-----------------------------------------------------------------------------
# ANALYSIS TYPE CONFIGURATION
#-----------------------------------------------------------------------------
# The type of analysis to perform, affecting the level of detail and focus areas

# Options:
# - standard: Basic health and status information
# - health: Focus on cluster health metrics
# - performance: Focus on resource usage and performance
# - security: Focus on security configurations and issues
# - troubleshooting: Detailed analysis for problem identification
# - comprehensive: Most detailed analysis including all aspects
# - resource: Focus on resource allocation and usage
# - capacity: Focus on capacity planning and limits
analysis_type = "standard"

#-----------------------------------------------------------------------------
# CLUSTER METADATA VARIABLES
#-----------------------------------------------------------------------------
# Descriptive information about your cluster for documentation purposes
# These don't affect analysis but are included in reports

# The platform/environment where your Kubernetes cluster is running
cluster_platform = "MacBook Pro M1 Max"

# CPU allocation information for your cluster
cluster_cpu = "6-Core CPU"

# Memory allocation information for your cluster
cluster_memory = "12GB"

# The container runtime used by your Kubernetes cluster
cluster_runtime = "Docker"

#-----------------------------------------------------------------------------
# DEBUGGING OPTIONS
#-----------------------------------------------------------------------------
# Advanced options for troubleshooting the analyzer itself

# Generate additional raw debug files (useful for troubleshooting)
# Set to true only when you need deeper insights into raw cluster data
debug_mode = false
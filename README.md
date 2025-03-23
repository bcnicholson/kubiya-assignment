# Kubernetes Cluster Analyzer with Terraform and AI Integration

This project implements a solution that collects information from a Kubernetes cluster using Terraform and leverages AI tools to analyze the cluster's health status. The system is designed to work with a local Minikube cluster for development and testing purposes.

## Architecture Overview

The solution consists of the following components:

1. **Local Kubernetes Cluster**: A Minikube-based cluster running on a MacBook Pro (M1 Max chip, 10-Core CPU, 32-Core GPU, 64GB memory)
2. **Terraform Modules**: 
   - A cluster analyzer module that collects detailed information about pods, nodes, and deployments
   - A root module that calls the analyzer and formats outputs
3. **AI Integration**: The system generates a structured prompt for AI analysis and submits it to an AI service for insights.

### Design Choices

- **Local Operation**: All components run locally to avoid cloud costs and simplify the setup.
- **Modular Structure**: The Terraform code is organized in modules for better reusability and maintainability.
- **Flexible Configuration**: The analyzer module can be configured to include or exclude certain information types.
- **Structured Data for AI**: The system formats cluster data specifically for optimal AI analysis.
- **Hierarchical Pod Groupings**: Pods are organized by namespace and status, with detailed information at each level.
- **Health Threshold Metrics**: Configurable health thresholds with detailed analysis and reporting.
- **Detailed Node Analysis**: Optional collection of node information including capacity and conditions.
- **Deployment Analysis**: Optional analysis of deployments with replica status tracking.

## Setup Instructions

### Prerequisites

1. Install required tools:
   ```bash
   # Install Minikube
   brew install minikube
   
   # Install kubectl
   brew install kubectl
   
   # Install Terraform
   brew install terraform
   ```

### Kubernetes Cluster Setup

1. Start Minikube with appropriate resources:
   ```bash
   minikube start --cpus 6 --memory 12288
   ```

2. Verify the cluster is operational:
   ```bash
   kubectl get nodes
   ```

### Deploy Test Applications

1. Create a dedicated namespace:
   ```bash
   kubectl create namespace test-apps
   ```

2. Deploy web server (nginx):
   ```bash
   kubectl apply -f kubernetes/nginx.yaml
   ```

3. Deploy database (PostgreSQL):
   ```bash
   kubectl apply -f kubernetes/postgres.yaml
   ```

4. Deploy cache (Redis):
   ```bash
   kubectl apply -f kubernetes/redis.yaml
   ```

5. (Optional) Create a failing pod:
   ```bash
   kubectl apply -f kubernetes/failing-pod.yaml
   ```

6. Verify the applications are running:
   ```bash
   kubectl get pods -n test-apps
   ```

### Terraform Module Usage

1. Clone this repository:
   ```bash
   git clone https://github.com/bcnicholson/kubiya-assignment.git
   cd kubiya-assignment
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Plan the execution:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

5. Check the output files:
   ```bash
   ls -la cluster-analysis/
   ```

### AI Integration

1. Take the AI prompt file:
   ```bash
   cat cluster-analysis/ai_prompt.md
   ```

2. Submit the prompt to an AI service (Claude, ChatGPT, etc.).

3. Document the AI's analysis and compare it with your understanding of the cluster's state.

## Kubernetes Configuration Files

The `kubernetes/` directory contains YAML files for deploying test applications:

- `nginx.yaml`: Deploys a simple web server with 2 replicas
- `postgres.yaml`: Deploys a PostgreSQL database
- `redis.yaml`: Deploys a Redis cache instance
- `failing-pod.yaml`: Deploys a pod with an invalid image to simulate a failure

## Terraform Module Structure

```
.
├── main.tf                # Root module that calls the cluster-analyzer
├── variables.tf           # Root level variables
├── modules/
│   └── cluster-analyzer/  # Module to analyze Kubernetes cluster
│       ├── main.tf        # Main implementation
│       ├── variables.tf   # Input variables
│       └── outputs.tf     # Output definitions
├── kubernetes/            # Kubernetes YAML configurations
│   ├── nginx.yaml
│   ├── postgres.yaml
│   ├── redis.yaml
│   └── failing-pod.yaml
└── cluster-analysis/      # Generated output files (created by Terraform)
    ├── raw_pod_data.json                  # All pod data
    ├── cluster_summary.json               # High-level cluster summary
    ├── health_status.json                 # Health threshold metrics
    ├── problematic_pods.json              # Pods with issues
    ├── ai_prompt.md                       # AI analysis prompt
    ├── namespace_summary.json             # Details per namespace
    ├── status_summary.json                # Details per status
    ├── pods_by_namespace_and_status.json  # Hierarchical grouping
    ├── node_data.json                     # Node information (optional)
    └── deployment_data.json               # Deployment information (optional)
```

## Module Variables

### Root Module Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| output_path | Path to store the output files | string | "./cluster-analysis" |

### Cluster Analyzer Module Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| output_path | Path where the output files will be stored | string | "./output" |
| include_node_info | Whether to include node information | bool | false |
| include_deployment_details | Whether to include deployment details | bool | false |
| health_threshold | Percentage of running pods required for cluster to be considered healthy | number | 90 |
| ignore_namespaces | List of namespaces to ignore in the analysis | list(string) | ["kube-system", "kube-public", "kube-node-lease"] |

## Module Outputs

The module provides multiple outputs organized by category:

1. **Core Cluster Information**: 
   - `namespace_list`: List of all namespaces
   - `cluster_summary`: Complete cluster health summary

2. **Pod Status**: 
   - `running_pods_count`: Number of running pods
   - `problematic_pods_count`: Number of pods with issues
   - `problematic_pods`: Details of problematic pods

3. **Pod Groupings**:
   - `pods_by_namespace`: Pods grouped by namespace
   - `pods_by_status`: Pods grouped by status
   - `pods_by_namespace_and_status`: Hierarchical grouping by namespace and status
   - `namespace_summary`: Detailed namespace information with pod names
   - `status_summary`: Detailed status information with pod names

4. **Health Metrics**:
   - `health_percentage`: Percentage of pods in running state
   - `health_threshold`: Configured threshold
   - `is_healthy`: Whether the cluster meets the threshold
   - `health_status`: "Healthy" or "Unhealthy" status

5. **AI Analysis**:
   - `ai_prompt`: Generated AI prompt for analysis
   - File paths to all generated output files

## Implemented Bonus Challenges

Based on the assignment's bonus challenges section, the following have been implemented:

1. **Custom Metrics**: 
   - Added collection of health percentage metrics based on running pods
   - Implemented configurable health thresholds with status reporting
   - Collected and analyzed container status within pods

2. **Advanced AI Prompting**: 
   - Designed specialized prompts that include detailed pod groupings
   - Created a hierarchical data presentation for better AI analysis
   - Included specific diagnostic questions in the prompt to direct the AI analysis

## Additional Enhancements Beyond Requirements

Beyond the core requirements and bonus challenges, the solution includes:

1. **Detailed Pod Groupings**: 
   - Implemented hierarchical grouping by namespace and status
   - Added pod names to groupings for more detailed analysis
   - Created dedicated output files for different grouping perspectives

2. **Extended Data Collection**:
   - Optional node information collection
   - Optional deployment analysis
   - Detailed container status tracking within pods

3. **Health Analysis**:
   - Configurable health threshold with detailed reporting
   - Classification of cluster as "Healthy" or "Unhealthy"
   - Formatting of health percentages for readability

4. **Code Quality Improvements**:
   - Organized code into logical sections for maintainability
   - Added comprehensive error handling
   - Implemented flexible configuration options

## Future Improvements

These improvements align with the remaining bonus challenges and future enhancements:

1. **Historical Tracking**: Implement a mechanism to track cluster health over time by storing and comparing analysis results.

2. **Deployment Automation**: Create a Terraform template that can deploy new applications based on analysis results.

3. **Direct AI Integration**: Obtain an API key for an LLM service and modify the Terraform module to send the structured data directly to the LLM for analysis.

## Challenges and Solutions

### Challenges Faced

1. **Type Safety in Terraform**: Resolved inconsistent conditional result types by using separate outputs for enhanced and basic summaries.
2. **Circular Dependencies**: Fixed by properly structuring local variables to avoid circular references.
3. **Data Structure Complexity**: Addressed by creating intermediate data structures with clear transformation steps.
4. **Handling Optional Features**: Implemented robust null checking and conditional resource creation.

### Solutions Implemented

1. **Modular Code Structure**: Organized code into clear functional sections for better maintainability.
2. **Comprehensive Error Handling**: Added proper handling for potential null values and missing data.
3. **Enhanced Grouping Logic**: Implemented hierarchical groupings with pod names for detailed analysis.
4. **Format Standardization**: Applied consistent formatting for decimal values and JSON outputs.

## Screen Captures

- [Add screenshots of your running cluster, Terraform execution, and AI analysis here]
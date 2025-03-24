# Kubernetes Cluster Analysis with Terraform & AI Integration

This project implements an integrated solution that collects information from a Kubernetes cluster using Terraform and leverages AI capabilities to analyze the cluster's health status. The system works with a local Minikube Kubernetes environment and uses free AI tools for analysis.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
- [Usage](#usage)
- [Analysis Types](#analysis-types)
- [Implementation Details](#implementation-details)
- [Screenshots](#screenshots)
- [Reflection and Learnings](#reflection-and-learnings)
- [Future Improvements](#future-improvements)

## Overview

This solution automates the collection of Kubernetes cluster health data and prepares it for AI analysis. The system:

1. Connects to a local Kubernetes cluster (Minikube)
2. Collects detailed information about pods, nodes, and deployments
3. Processes this information into structured formats
4. Generates AI prompts tailored for different types of analysis
5. Outputs both raw data and processed information as JSON files
6. Creates markdown files with AI prompts ready for submission to AI tools

## Architecture

The architecture consists of two main components:

1. **Terraform Infrastructure**:
   - Root module that configures providers and handles variable inputs
   - Custom `cluster-analyzer` module that connects to Kubernetes and processes data
   - Local file outputs with structured data and AI prompts

2. **AI Integration**:
   - Generated prompts ready for submission to AI tools like Claude
   - Context-rich input with cluster details
   - Multiple analysis types (health, performance, security, etc.)

![Architecture Diagram](/screenshots/Kubiya-assignment-arch.png)

### Key Components

- **Terraform Root Module**: Configures providers and passes variables to the cluster analyzer module
- **Cluster Analyzer Module**: Collects and processes Kubernetes resources data
- **Output Files**: JSON data files and AI-ready markdown prompts
- **AI Analysis**: External component where generated prompts are submitted to AI tools

## Prerequisites

- A computer with at least 4GB RAM and 20GB free disk space
- Basic familiarity with command line operations
- Basic understanding of YAML and infrastructure concepts
- The following tools installed:
  - Minikube (for local Kubernetes)
  - Kubectl (Kubernetes command-line tool)
  - Terraform

## Setup Instructions

### 1. Install Required Tools

**For MacOS:**

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Minikube
brew install minikube

# Install kubectl
brew install kubectl

# Install Terraform
brew install terraform
```

**For Linux:**

```bash
# Install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform
```

### 2. Start Minikube

```bash
# Start Minikube with appropriate resources
minikube start --cpus=6 --memory=12288

# Enable metrics-server for resource metrics collection
minikube addons enable metrics-server
```

### 3. Deploy Test Applications

```bash
# Create a dedicated namespace
kubectl create namespace test-apps

# Deploy a web server (nginx)
kubectl -n test-apps create deployment nginx --image=nginx:latest --replicas=2

# Deploy a database (PostgreSQL)
kubectl -n test-apps create deployment postgres --image=postgres:latest --replicas=1
kubectl -n test-apps set env deployment/postgres POSTGRES_PASSWORD=password

# Deploy a cache/message broker (Redis)
kubectl -n test-apps create deployment redis --image=redis:latest --replicas=1

# Optional: Create a failing pod
kubectl -n test-apps run failing-pod --image=busybox:invalid --command -- /bin/sh -c "exit 1"
```

### 4. Clone and Configure the Project

```bash
git clone https://github.com/bcnicholson/kubiya-assignment.git
cd kubiya-assignment

# Review and modify terraform.tfvars as needed
# Example: Adjust the cluster_platform, cluster_cpu, and cluster_memory variables
```

### 5. Initialize and Apply Terraform

```bash
# Initialize Terraform
terraform init

# Apply the configuration
terraform apply -auto-approve
```

### 6. Submit AI Prompt for Analysis

Take the generated AI prompt from `./cluster-analysis/ai_prompt.md` and submit it to an AI service like Claude, ChatGPT, or Google Bard.

## Usage

### Basic Usage

1. Configure parameters in `terraform.tfvars` to match your environment:

```hcl
# terraform.tfvars

# Kubernetes Configuration
config_path = "~/.kube/config"
config_context = "minikube"

# Output path
output_path = "./cluster-analysis"

# Enable features
include_resource_metrics = true
include_node_info = true
include_deployment_details = true

# Set health threshold
health_threshold = 90

# Set analysis type
analysis_type = "comprehensive"

# Set namespaces to ignore
ignore_namespaces = ["kube-system", "kube-public", "kube-node-lease"]

# Cluster information
cluster_platform = "MacBook Pro M1 Max"
cluster_cpu = "6-Core CPU"
cluster_memory = "12GB"
```

2. Run Terraform:

```bash
terraform apply
```

3. Check output files in the specified output directory:

```bash
ls -la ./cluster-analysis/
```

4. Take the generated AI prompt from `./cluster-analysis/ai_prompt.md` and submit it to your preferred AI service.

### Configuration Variables

The module uses several variables that represent important architectural decisions in the design:

| Variable                   | Description                                             | Architectural Significance                                 |
|----------------------------|---------------------------------------------------------|-----------------------------------------------------------|
| `config_path`              | Path to Kubernetes config                               | Allows flexible connectivity to different K8s environments |
| `config_context`           | Kubernetes context to use                               | Enables multi-cluster support from a single config         |
| `output_path`              | Directory for output files                              | Separates infrastructure code from analysis artifacts      |
| `include_resource_metrics` | Whether to collect resource usage data                  | Optional performance analysis capability                   |
| `include_node_info`        | Whether to include node information                     | Infrastructure-level monitoring capability                 |
| `include_deployment_details` | Whether to collect deployment data                    | Application-level monitoring capability                    |
| `health_threshold`         | Percentage of pods needed for "healthy" status          | Configurable SLA definition                                |
| `ignore_namespaces`        | Namespaces to exclude from analysis                     | Control plane isolation from application monitoring        |
| `analysis_type`            | Type of AI analysis to perform                          | Specialized analysis capabilities                          |
| `cluster_platform`         | Description of host platform                            | Contextual information for AI analysis                     |
| `cluster_cpu`              | CPU resources allocated to cluster                      | Resource context for AI recommendations                    |
| `cluster_memory`           | Memory resources allocated to cluster                   | Resource context for AI recommendations                    |
| `debug_mode`               | Whether to generate additional debug outputs            | Troubleshooting capability                                 |

These variables allow the solution to be highly customizable while maintaining a clean separation of concerns between data collection, processing, and analysis.

### Customizing Analysis

To customize the analysis type, modify the `analysis_type` variable in `terraform.tfvars`:

```hcl
# Choose from: standard, health, performance, security, troubleshooting, comprehensive, resource, capacity
analysis_type = "security"
```

## Analysis Types

The module supports multiple analysis types, each generating a specialized AI prompt. This implementation of advanced AI prompting exceeds the requirements of the assignment by providing 8 different analysis types:

1. **standard**: Basic cluster health and status assessment
2. **health**: Focused health assessment with remediation recommendations
3. **performance**: Performance optimization analysis
4. **security**: Security assessment and best practices
5. **troubleshooting**: Step-by-step troubleshooting guide with kubectl commands
6. **comprehensive**: Complete analysis covering health, performance, and security
7. **resource**: Resource utilization and optimization recommendations
8. **capacity**: Capacity planning and scaling guidance

Each analysis type adjusts the prompting strategy to get specialized insights from the AI service. For example, the security prompt focuses on namespace isolation and container image analysis, while the troubleshooting prompt emphasizes diagnostic commands and verification procedures.

## Implementation Details

### Terraform Module Structure

```
.
├── main.tf                  # Root module configuration
├── variables.tf             # Root variable definitions
├── terraform.tfvars         # Variable values
├── kubernetes/              # Kubernetes manifests subfolder
│   └── *.yaml               # Kubernetes manifests
├── modules/
│   └── cluster-analyzer/    # Custom analyzer module
│       ├── main.tf          # Module implementation
│       ├── variables.tf     # Module variable definitions
│       └── outputs.tf       # Module outputs
└── cluster-analysis/        # Generated output files
```

### Advanced Features

#### Debug Mode

The module includes a debug mode that generates additional files for troubleshooting. When `debug_mode` is set to `true` in `terraform.tfvars`, the module will:

- Generate raw metrics data files for debugging
- Output pod metrics structure information
- Run kubectl commands to verify metrics API status
- Create detailed resource utilization files

This is particularly useful when:
- Metrics are not being collected correctly
- Troubleshooting complex resource utilization issues 
- Verifying API connectivity

#### Kubernetes Manifests

To deploy the Kubernetes test applications, you can use the manifest files in the `kubernetes/` subfolder. This provides a more declarative approach compared to the imperative kubectl commands mentioned in the setup instructions.

### Data Collection Process

1. **Pod Information**: Collects pod names, namespaces, statuses, containers, and conditions
2. **Node Information** (optional): Collects node capacity, conditions, and resource usage
3. **Deployment Information** (optional): Collects replica counts and availability
4. **Resource Metrics** (optional): Collects CPU and memory usage via the metrics API

### Data Processing

1. Filter namespaces based on ignore list
2. Process all pods into a normalized format
3. Calculate health metrics and status
4. Group pods by namespace and status
5. Identify problematic resources
6. Generate summary statistics
7. Format data for AI analysis

### Output Files

The module generates several output files:

- `ai_prompt.md`: AI prompt in markdown format
- `cluster_summary.json`: Summary of cluster health
- `raw_pod_data.json`: Raw pod information
- `health_status.json`: Health metrics and status
- `problematic_pods.json`: Details of problematic pods
- `namespace_summary.json`: Pod summaries by namespace
- `status_summary.json`: Pod summaries by status
- `pods_by_namespace_and_status.json`: Hierarchical pod grouping

## Screenshots

As required by the Home Assignment, here are screenshots demonstrating the solution:

### Kubernetes Cluster Setup and Operation
![Minikube Setup](/screenshots/minikubesetup.png)
*Screenshot showing the setup and running Minikube cluster with appropriate resources allocated*

![Kubernetes Running](/screenshots/podsrunning.png)
*Screenshot showing pods in test-apps namespace on running cluster*

### Terraform Execution Results

![Terraform Apply](/screenshots/terraformapply.png)
*Screenshot showing successful execution of Terraform apply command*

![Terraform Outputs](/screenshots/terraformoutputs.png)
*Screenshot showing Terraform outputs with cluster health metrics*

### Generated Files and Prompts

![Output Files](/screenshots/outputfiles.png)
*Screenshot showing the generated analysis files in the output directory*

![AI Prompt Example](/screenshots/enhancedstandardaiprompt.png)
*Screenshot showing an example of the standard generated AI prompt markdown file*

### AI Analysis Results

![AI Analysis Overview](/screenshots/ai-analysis-overview.png)
*Screenshot showing the AI service analyzing the cluster data*

![AI Recommendations](/screenshots/ai-recommendations.png)
*Screenshot showing specific recommendations provided by the AI*

### Optional Bonus Challenge Results

![Resource Metrics](/screenshots/resource-metrics.png)
*Screenshot showing the collected resource metrics (Bonus Challenge)*

![Advanced AI Prompting](/screenshots/advanced-prompting.png)
*Screenshot demonstrating the specialized AI prompting capabilities (Bonus Challenge)*

## Reflection and Learnings

### Technical Challenges

1. **Metrics Collection**: Integrating with the Kubernetes metrics API required careful handling of API versions and fallback mechanisms. The metrics server addon in Minikube needed to be enabled and properly configured. The PodMetrics implementation, in particular, required extensive troubleshooting:
   
   - Used `kubectl get apiservice` and `kubectl api-resources` to explore API functionality and fields, which was essential for properly using the Terraform Kubernetes provider
   - Discovered an issue with the `kubernetes_resources` data source when targeting `kind:PodMetrics` 
   - Implemented a workaround using `local-exec` to run `kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods` and output to a local JSON file
   - Created a fallback mechanism when metrics are unavailable to maintain module stability
   - Added comprehensive debug outputs to help diagnose metrics collection issues

2. **Complex Data Structures**: Processing nested Kubernetes resources into structured formats required careful handling of optional values and null checks. Terraform's HCL syntax for complex data transformations required thoughtful design:
   
   - Implemented extensive null handling with `try()` functions
   - Created structured data transformations for nested pod, node, and deployment information
   - Built hierarchical groupings of resources with multiple index levels
   - Designed flexible output structures that work with or without optional components

3. **AI Prompt Engineering**: Crafting effective AI prompts that would generate useful analysis required several iterations. The prompt needed to contain enough context but be concise enough for AI processing:
   
   - Created specialized prompt formats for different analysis types
   - Balanced technical detail with prompt clarity
   - Structured data presentation to highlight the most relevant metrics
   - Designed specific analytical questions to guide AI response

### Key Learnings

1. **Terraform Provider Capabilities**: Learned the extensive capabilities of the Kubernetes provider in Terraform, which goes well beyond simple resource creation.

2. **Data Processing in HCL**: Gained experience with Terraform's data processing capabilities, using locals, for expressions, and dynamic blocks to transform data.

3. **Cross-Tool Integration**: Developed skills in creating integrations between different tools (Kubernetes, Terraform, and AI services) using structured data formats.

4. **AI Prompt Design**: Learned how to effectively structure information for AI analysis, including providing context, specific questions, and formatting guidance.

## Completed Bonus Challenges

This implementation has successfully completed the following bonus challenges from the assignment:

1. **Custom Metrics**: Added collection of resource usage statistics through the Kubernetes metrics API. The module collects CPU and memory metrics for pods and nodes when `include_resource_metrics` is enabled.

2. **Advanced AI Prompting**: Implemented specialized prompts that produce different types of analysis. The module supports 8 different analysis types: standard, health, performance, security, troubleshooting, comprehensive, resource, and capacity - each producing tailored AI prompts.

## Future Improvements

1. **Further Custom Metrics Collection**: Extend the module to collect application-specific custom metrics from the Prometheus API.

2. **Deployment Automation**: Create a Terraform template that can deploy new applications based on the AI's recommendations.

3. **Historical Tracking**: Implement a mechanism to track cluster health over time, storing historical data in a database or time-series storage.

4. **Further AI Prompt Enhancements**: Expand the specialized prompts for more targeted use cases like cost optimization, security compliance, and upgrade readiness.

5. **Direct AI Integration**: Integrate with AI service APIs to automate the submission and retrieval of analysis results.

6. **Visualization**: Add visualization capabilities to display cluster health metrics and AI insights through a web dashboard.

7. **Multi-Cluster Support**: Extend the module to analyze multiple clusters and compare their health status.

8. **Alerting Integration**: Connect with alerting systems to send notifications when cluster health drops below thresholds.

9. **Enhanced Security Analysis**: Add deeper security analysis capabilities, such as policy compliance checking and vulnerability assessment.

10. **Resource Utilization Trends**: Implement tracking of resource utilization trends to aid in capacity planning.

---

This project demonstrates the integration of infrastructure automation (Terraform) with AI analysis capabilities to create a powerful cluster management tool. By automating the collection and analysis of Kubernetes cluster data, it provides valuable insights that can help improve cluster health, performance, and security.

## License

MIT License

Copyright (c) 2025 

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

Contributions are welcome and encouraged! This project aims to create a valuable tool for the Kubernetes community, and your expertise can help make it even better.

### Ways to Contribute

- **Bug Reports**: Submit issues for any bugs or errors you encounter
- **Feature Requests**: Suggest new features or improvements
- **Code Contributions**: Submit pull requests for bug fixes or new features
- **Documentation**: Improve explanations, add examples, or fix typos
- **Testing**: Try the tool in different environments and report your findings

If you're interested in contributing, please:

1. Fork the repository
2. Create a new branch for your feature or fix
3. Add your changes
4. Submit a pull request

All contributions, big or small, are appreciated! Let's build a better Kubernetes analysis tool together.
# Kubernetes Cluster Analyzer with Terraform and AI Integration

This project implements a solution that collects information from a Kubernetes cluster using Terraform and leverages AI tools to analyze the cluster's health status. The system is designed to work with a local Minikube cluster for development and testing purposes.

## Architecture Overview

The solution consists of the following components:

1. **Local Kubernetes Cluster**: A Minikube-based cluster that hosts test applications.
2. **Terraform Modules**: 
   - A cluster analyzer module that collects information about pods, nodes, and deployments
   - A root module that calls the analyzer and formats outputs
3. **AI Integration**: The system generates a structured prompt for AI analysis and submits it to an AI service (e.g., Claude, ChatGPT) for insights.

### Design Choices

- **Local Operation**: All components run locally to avoid cloud costs and simplify the setup.
- **Modular Structure**: The Terraform code is organized in modules for better reusability and maintainability.
- **Flexible Configuration**: The analyzer module can be configured to include or exclude certain information types.
- **Structured Data for AI**: The system formats cluster data specifically for optimal AI analysis.

## Setup Instructions

### Prerequisites

1. Install required tools:
   ```bash
   # Install Minikube (for local Kubernetes)
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install minikube-linux-amd64 /usr/local/bin/minikube
   
   # Install kubectl (Kubernetes CLI)
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   
   # Install Terraform
   curl -fsSL https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip -o terraform.zip
   unzip terraform.zip
   sudo mv terraform /usr/local/bin/
   ```

### Kubernetes Cluster Setup

1. Start Minikube with appropriate resources:
   ```bash
   minikube start --cpus=2 --memory=4096 --driver=docker
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

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Plan the execution:
   ```bash
   terraform plan
   ```

3. Apply the configuration:
   ```bash
   terraform apply
   ```

4. Check the output files:
   ```bash
   ls -la output/
   ```

### AI Integration

1. Take the AI prompt file:
   ```bash
   cat output/ai_prompt.md
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
└── output/                # Generated output files (created by Terraform)
    ├── raw_pod_data.json
    ├── cluster_summary.json
    ├── problematic_pods.json
    └── ai_prompt.md
```

## Bonus Features Implemented

- **Custom Metrics**: The module collects and analyzes pod states and conditions.
- **Advanced AI Prompting**: The prompt is structured to generate specific insights about cluster health.
- **Deployment Tracking**: Optional collection and analysis of deployment statuses.
- **Node Information**: Optional collection and analysis of node capacity and status.

## Future Improvements

1. **Historical Tracking**: Implement time-series storage of cluster metrics.
2. **Automatic Remediation**: Add Terraform resources to fix common issues.
3. **Custom Resource Support**: Extend to analyze Kubernetes custom resources.
4. **Direct AI API Integration**: Connect directly to AI APIs for automated analysis.
5. **Visualization**: Add visualization capabilities for the cluster state.

## Challenges Faced

- Kubernetes API interaction required careful consideration of data structures.
- Structuring data for AI analysis required balancing detail with clarity.
- Handling potential missing or null values in Kubernetes resources.

## Screen Captures

- [Add screenshots of your running cluster, Terraform execution, and AI analysis here]
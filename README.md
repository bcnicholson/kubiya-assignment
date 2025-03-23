# Kubiya Assignment - Kubernetes Cluster Analyzer

## Project Overview
This repository contains Terraform configurations and Kubernetes manifests for a cluster analysis project. The project includes:
- A Terraform module for cluster analysis
- Kubernetes deployment manifests for various services (nginx, postgres, redis)
- A failing pod configuration for testing purposes
- Screenshots and analysis documentation
- Optional video demonstration

## Directory Structure
```
BNicholson_KubiyaEvaluation.zip/
├── kubiya-assignment/
│   ├── modules/
│   │   └── cluster-analyzer/    # Terraform module for cluster analysis
│   │       ├── main.tf         # Main module configuration
│   │       ├── outputs.tf      # Module outputs
│   │       └── variables.tf    # Module variables
│   ├── main.tf                 # Root Terraform configuration
│   ├── outputs.tf              # Root module outputs
│   ├── nginx-deployment.yaml   # Nginx deployment manifest
│   ├── postgres-deployment.yaml # PostgreSQL deployment manifest
│   ├── postgres-secret.yaml    # PostgreSQL secret manifest
│   ├── redis-deployment.yaml   # Redis deployment manifest
│   └── failing-pod.yaml        # Optional failing pod manifest
│   └── README.md              # Project documentation
├── screenshots/               # Project screenshots
│   ├── kubernetes_pods.png    # Kubernetes pods screenshot
│   ├── terraform_apply.png    # Terraform apply screenshot
│   └── gemini_analysis.png    # Gemini analysis screenshot
├── gemini_analysis.txt        # Analysis results
└── video_demo.mp4            # Optional video demonstration
```

## Getting Started

### Prerequisites
- Terraform >= 1.0.0
- Kubernetes cluster (local - minikube)
- kubectl CLI tool
- Kubernetes provider for Terraform
- Local provider for Terraform

### Setup
1. Clone this repository
2. Start your local Kubernetes cluster:
   ```bash
   minikube start
   ```
3. Configure your Kubernetes context:
   ```bash
   kubectl config use-context minikube
   ```
4. Initialize Terraform:
   ```bash
   terraform init
   ```
5. Review the planned changes:
   ```bash
   terraform plan
   ```
6. Apply the configuration:
   ```bash
   terraform apply
   ```

## Module Documentation
The `cluster-analyzer` module provides functionality for analyzing Kubernetes cluster resources and states. See the module's README for detailed usage instructions.

## Kubernetes Resources
The project includes several Kubernetes manifests:
- Nginx deployment for web serving
- PostgreSQL deployment with secret management
- Redis deployment for caching
- Optional failing pod for testing purposes

## Development Guidelines
This project follows the guidelines specified in `.cursorrules`, including:
- Modular code organization for Kubernetes resources
- Version control best practices
- Security-first approach for Kubernetes RBAC and secrets
- Testing and validation requirements
- Documentation standards

## Contributing
1. Create a new branch for your changes
2. Follow the established code organization patterns
3. Document your changes thoroughly
4. Test your changes before submitting
5. Ensure all sensitive data is properly handled using Kubernetes secrets

## Resources
- [Terraform Documentation](https://www.terraform.io/docs)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/kubernetes-api/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/) 
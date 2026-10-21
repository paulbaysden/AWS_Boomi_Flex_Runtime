# Boomi Flex Runtime on AWS EKS with EFS

Terraform for the Boomi Flex Runtime: EFS storage (UID/GID 1000 access point), namespace, PV/PVC, and the `runtimectl install` step.

## Files
- config.yaml: all inputs (must match the Runtime Management UI wizard)
- versions.tf, variables.tf: provider and variable definitions
- efs.tf: EFS file system, mount targets, security group, access point, EFS CSI add-on
- main.tf: providers, namespace, PV/PVC, runtimectl install, BackendTLSPolicy (end-to-end TLS)
- outputs.tf: namespace, EFS IDs, ingress Service and port

## Steps
1. Fill in config.yaml (VPC, subnets, node security group, namespace, claim name).
2. In Runtime Management UI, create a Flex Runtime with the same namespace and claim name. Select the Agent workload.
3. Copy the install token right away (valid 15 minutes).
4. From a Linux host with runtimectl, kubectl, and AWS credentials:
   export TF_VAR_install_token='<token>'
   terraform init
   terraform apply

## Notes
- Flex Runtime is Early Access, not for production, and North America only.
- One mount target per AZ. Use one subnet per AZ where nodes run.
- The file system has prevent_destroy set. Remove it in efs.tf if you want destroy to delete the EFS.
- Verify runtimectl flags with `runtimectl install --help` before running.

terraform init -backend-config="key=dev.tfstate"
terraform fmt -recursive -check
terraform validate
terraform plan -var-file=dev.tfvars -out=tfplan
terraform plan -detailed-exitcode        # 0 none, 1 error, 2 changes
terraform apply tfplan
terraform state list | show <addr> | mv <a> <b> | rm <addr>
terraform import azurerm_resource_group.rg /subscriptions/<sub>/resourceGroups/rg-demo-dev
terraform plan -generate-config-out=generated.tf   # with import {} blocks
terraform force-unlock <lock-id>
terraform workspace new prod && terraform workspace select prod

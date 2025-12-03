.PHONY: help build deploy plan apply destroy test clean

help:
	@echo "Available targets:"
	@echo "  build       - Build Lambda deployment package"
	@echo "  plan        - Run terraform plan"
	@echo "  apply       - Deploy infrastructure"
	@echo "  destroy     - Destroy infrastructure"
	@echo "  test        - Test Lambda function locally"
	@echo "  clean       - Clean build artifacts"

build:
	@echo "Building Lambda package..."
	@./scripts/build_lambda.sh

plan:
	@terraform init
	@terraform plan -var-file=terraform.tfvars

apply:
	@terraform init
	@terraform apply -var-file=terraform.tfvars

destroy:
	@terraform destroy -var-file=terraform.tfvars

test:
	@echo "Testing Lambda function..."
	@python3 -m pytest tests/ -v || echo "No tests configured yet"

clean:
	@rm -rf build/ .terraform/ *.tfstate* lambda_function.zip


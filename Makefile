.PHONY: help validate-local terraform-wrapper-tests aws-s3-state-creator-tests

help:
	@echo "Available targets:"
	@echo "  validate-local                Run the local GitHub Actions simulator"
	@echo "  terraform-wrapper-tests       Run Terraform wrapper shell suite"
	@echo "  aws-s3-state-creator-tests    Run AWS S3 state creator shell suite"

validate-local:
	@./validate-repo-locally.sh

terraform-wrapper-tests:
	@bash tests/scripts/terraform_wrappers/run.sh

aws-s3-state-creator-tests:
	@bash tests/scripts/aws_terraform_s3_state_creator/run.sh

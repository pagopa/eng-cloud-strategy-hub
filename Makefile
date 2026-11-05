.PHONY: help validate-local test python-tests terraform-wrapper-tests aws-s3-state-creator-tests aws-dynamic-states-tests

help:
	@echo "Available targets:"
	@echo "  validate-local                Run the local GitHub Actions simulator"
	@echo "  test                          Run every test suite under tests/"
	@echo "  python-tests                  Run every Python test directory under tests/"
	@echo "  terraform-wrapper-tests       Run the cross-provider terraform.sh shell suite"
	@echo "  aws-s3-state-creator-tests    Run AWS S3 state creator shell suite"
	@echo "  aws-dynamic-states-tests      Run AWS dynamic states shell suite"

validate-local:
	@./validate-repo-locally.sh

test: python-tests terraform-wrapper-tests aws-s3-state-creator-tests aws-dynamic-states-tests

# Each directory runs alone because test directories mirror hyphenated component names.
python-tests:
	@set -e; for test_dir in $$(find tests -name 'test_*.py' -exec dirname {} \; | sort -u); do \
		echo "==> $$test_dir"; \
		python3 -m unittest discover -s "$$test_dir" -p 'test_*.py'; \
	done

terraform-wrapper-tests:
	@bash tests/scripts/cross-provider/terraform-sh/run.sh

aws-s3-state-creator-tests:
	@bash tests/scripts/aws/aws-terraform-s3-state-creator/run.sh

aws-dynamic-states-tests:
	@bash tests/scripts/aws/terraform-dynamic-states/run.sh

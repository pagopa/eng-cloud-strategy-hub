.PHONY: help validate-local test python-tests terraform-wrapper-tests aws-s3-state-creator-tests aws-dynamic-states-tests

help:
	@echo "Available targets:"
	@echo "  validate-local                Run the local GitHub Actions simulator"
	@echo "  test                          Run every test suite under tests/"
	@echo "  python-tests                  Run every Python test directory under tests/"
	@echo "  terraform-wrapper-tests       Run the cross-provider terraform.sh shell suite"
	@echo "  aws-s3-state-creator-tests    Run AWS S3 state creator shell suite"
	@echo "  aws-dynamic-states-tests      Run AWS dynamic states shell suite"
	@echo "  terraform-backup-check        Run credential-free native backup module checks"

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

TERRAFORM ?= terraform
TERRAFORM_BACKUP_CORE = terraform/aws/modules/terraform-aws-backup
TERRAFORM_BACKUP_ALERTING = terraform/aws/modules/terraform-aws-backup-alerting
TERRAFORM_BACKUP_COVERAGE = terraform/aws/modules/terraform-aws-backup-coverage
TERRAFORM_BACKUP_PUBLIC_ROOTS = \
	$(TERRAFORM_BACKUP_CORE) \
	$(TERRAFORM_BACKUP_ALERTING) \
	$(TERRAFORM_BACKUP_COVERAGE) \
	$(TERRAFORM_BACKUP_CORE)/modules/backup-plan \
	$(TERRAFORM_BACKUP_CORE)/modules/presets/archival \
	$(TERRAFORM_BACKUP_CORE)/modules/presets/hourly-backup \
	$(TERRAFORM_BACKUP_CORE)/modules/presets/long-retention \
	$(TERRAFORM_BACKUP_CORE)/modules/presets/weekly-full
TERRAFORM_BACKUP_EXAMPLE_ROOTS = \
	$(TERRAFORM_BACKUP_CORE)/examples/production \
	$(TERRAFORM_BACKUP_CORE)/examples/non-production \
	$(TERRAFORM_BACKUP_CORE)/examples/continuous-pitr \
	$(TERRAFORM_BACKUP_CORE)/examples/nonprod-compliance-optin \
	$(TERRAFORM_BACKUP_CORE)/examples/by-service-type \
	$(TERRAFORM_BACKUP_CORE)/examples/with-extra-plans \
	$(TERRAFORM_BACKUP_ALERTING)/examples \
	$(TERRAFORM_BACKUP_COVERAGE)/examples
TERRAFORM_BACKUP_FIXTURE_ROOTS = \
	$(TERRAFORM_BACKUP_CORE)/tests/fixtures/consumer \
	$(TERRAFORM_BACKUP_CORE)/tests/fixtures/provider-minimum
TERRAFORM_BACKUP_TEST_ROOTS = $(TERRAFORM_BACKUP_PUBLIC_ROOTS) $(TERRAFORM_BACKUP_EXAMPLE_ROOTS)
TERRAFORM_BACKUP_INIT_ROOTS = $(TERRAFORM_BACKUP_TEST_ROOTS) $(TERRAFORM_BACKUP_FIXTURE_ROOTS)
TERRAFORM_BACKUP_VALIDATE_ROOTS = $(filter-out $(TERRAFORM_BACKUP_CORE),$(TERRAFORM_BACKUP_PUBLIC_ROOTS)) $(TERRAFORM_BACKUP_EXAMPLE_ROOTS) $(TERRAFORM_BACKUP_FIXTURE_ROOTS)

.PHONY: terraform-backup-check terraform-backup-fmt terraform-backup-init terraform-backup-validate terraform-backup-tests terraform-backup-runtime-tests

terraform-backup-check:
	@$(MAKE) terraform-backup-fmt
	@$(MAKE) terraform-backup-init
	@$(MAKE) terraform-backup-validate
	@$(MAKE) terraform-backup-tests
	@$(MAKE) terraform-backup-runtime-tests

terraform-backup-fmt:
	@$(TERRAFORM) fmt -check -recursive "$(TERRAFORM_BACKUP_CORE)"
	@$(TERRAFORM) fmt -check -recursive "$(TERRAFORM_BACKUP_ALERTING)"
	@$(TERRAFORM) fmt -check -recursive "$(TERRAFORM_BACKUP_COVERAGE)"

terraform-backup-init:
	@set -eu; command -v "$(TERRAFORM)"; for root in $(TERRAFORM_BACKUP_INIT_ROOTS); do \
		printf '==> init %s\n' "$$root"; \
		$(TERRAFORM) -chdir="$$root" init -backend=false -input=false; \
	done

terraform-backup-validate:
	@set -eu; for root in $(TERRAFORM_BACKUP_VALIDATE_ROOTS); do \
		printf '==> validate %s\n' "$$root"; \
		$(TERRAFORM) -chdir="$$root" validate; \
	done

terraform-backup-tests:
	@set -eu; for root in $(TERRAFORM_BACKUP_TEST_ROOTS); do \
		set -- "$$root"/tests/*.tftest.hcl; \
		if [ ! -f "$$1" ]; then \
			printf 'Missing native test suite: %s\n' "$$root" >&2; exit 1; \
		fi; \
		printf '==> test %s\n' "$$root"; \
		$(TERRAFORM) -chdir="$$root" test; \
	done

terraform-backup-runtime-tests:
	@python3 -m pip install -r "$(TERRAFORM_BACKUP_COVERAGE)/tests/requirements.txt"
	@python3 -m unittest discover -s "$(TERRAFORM_BACKUP_COVERAGE)/tests" -p 'test_*.py'

Bootstrap script for the Terraform state S3 bucket.

Usage:
1) Configure AWS CLI with valid credentials.
2) Run the script:

```bash
./init_terraform_state_bucket.sh --profile <aws_profile> --region <aws_region> --account-name <account_name> --project-name <project_name> --terraform-principal-arn <principal_arn>
```

The script creates a bucket:
`<region>-<account>-<project>`

Best practices applied:
- Block public access
- Versioning
- Encryption SSE-S3

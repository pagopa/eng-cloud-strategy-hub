Bootstrap script for the Terraform state S3 bucket.

Usage:
1) Configure AWS CLI with valid credentials.
2) Run the script:

```bash
./init_terraform_state_bucket.sh --profile <aws_profile> --region <aws_region> --project-name <project_name>
```

The script creates a bucket:
`terraform-state-<project>-<region>`

Best practices applied:
- Block public access
- Versioning
- Encryption SSE-S3

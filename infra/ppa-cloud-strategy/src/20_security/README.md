S3 backend setup with native lockfile.

This module uses per-env files:
- `env/<env>/backend.tfvars` for the S3 backend.
- `env/<env>/backend.ini` for local script settings.

Required in `backend.ini`:
- `aws_region="eu-south-1"`

Optional in `backend.ini`:
- `aws_profile="your-aws-profile"`

Initialize with the helper script:
```bash
./terraform.sh init <env>
```

Note: the bucket must exist (created by the script in `scripts/init-account`).

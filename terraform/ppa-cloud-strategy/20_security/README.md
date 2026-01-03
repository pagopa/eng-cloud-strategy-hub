S3 backend setup with native lockfile.

1) Copy `backend.hcl.example` to `backend.hcl` and update the values.
2) Initialize:

```bash
terraform init -backend-config=backend.hcl
```

Note: the bucket must exist (created by the script in `scripts/init-account`).

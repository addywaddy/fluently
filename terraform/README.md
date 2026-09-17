# Fluently backup infrastructure

Terraform manages only the private `fluently-backups` bucket in Hetzner's `nbg1`
region. Fluently reuses the existing Chronologs VPS; this configuration does not
manage servers, firewalls, SSH keys, DNS, or any Chronologs resources.

The bucket was provisioned on 2026-09-17. The applied plan created one bucket,
changed/deleted nothing, and a subsequent plan reported no changes.

## Usage

Requires Terraform 1.5+. Supply credentials securely through:

- `TF_VAR_hetzner_s3_access_key`
- `TF_VAR_hetzner_s3_secret_key`

Optional non-secret overrides belong in ignored `terraform.tfvars`, using
`terraform.tfvars.example`. Do not copy credentials into tracked files.

```sh
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
umask 077
terraform -chdir=terraform plan -input=false -out=fluently.tfplan
terraform -chdir=terraform show -no-color fluently.tfplan
# Apply only after reviewing and authorizing the planned changes:
terraform -chdir=terraform apply fluently.tfplan
```

Commit `.terraform.lock.hcl` for reproducible provider versions. State, saved plans,
provider caches and variable files are ignored. Plans/state can contain credentials;
keep them private and securely back up the local `terraform.tfstate` file. Do not
reuse Chronologs' state. Generate a fresh plan after changing configuration.

The bucket has private ACLs, no public policy or browser CORS configuration,
`prevent_destroy`, and `force_destroy = false`. Litestream manages retention;
Terraform does not configure object expiration rules.

## Deployment

Kamal defaults `LITESTREAM_BUCKET` to `fluently-backups`. Override it if you explicitly
provision another bucket. The endpoint is `https://nbg1.your-objectstorage.com`.
Provide Litestream access credentials separately, preferably scoped to this bucket.

Follow [the deployment guide](../docs/deployment.md) to initialize the SQLite volume
and start the application/backup accessory. Creating a bucket does not start backups:
verify replication and a restore after deployment.

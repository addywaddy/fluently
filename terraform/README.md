# Fluently infrastructure

Terraform provisions a dedicated Hetzner VPS and private Litestream backup bucket.
This directory has its own local state and does not manage Chronologs infrastructure.
It reads an existing SSH key by name (default `adam@chronologs`) in the target Cloud project.

Defaults match the reference deployment: CPX22, Ubuntu 24.04, Nuremberg (`nbg1`), server
backups enabled, public HTTP/HTTPS, and SSH allowed from all IPs. Override
`ssh_source_cidrs` with stable administrator/VPN CIDRs if available. Port 4000 is not opened.
The private `fluently-backups` bucket has no public policy or browser CORS configuration.
Litestream handles retention; Terraform does not add object expiration rules.

## Plan only

Requires Terraform 1.5+ and the existing operator key in the target Hetzner project.
Provide credentials through environment variables or a password manager:

- `TF_VAR_hcloud_token`
- `TF_VAR_hetzner_s3_access_key`
- `TF_VAR_hetzner_s3_secret_key`

Never copy credentials into tracked files. Optional non-secret overrides can be placed in
ignored `terraform.tfvars` using `terraform.tfvars.example`. The chosen bucket name must
be available; planning a new bucket does not reserve the name or guarantee availability.

From the repository root:

```sh
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
umask 077
terraform -chdir=terraform plan -input=false -out=fluently.tfplan
terraform -chdir=terraform show -no-color fluently.tfplan
```

Planning reads provider APIs but does not create the server or bucket. Do not run apply
until the plan has been reviewed and provisioning explicitly authorized. A saved plan can
contain credentials even when terminal output marks them sensitive; keep it private.
Generate a fresh plan if configuration or credentials change.

Commit `.terraform.lock.hcl` for reproducible provider versions. Provider caches, local
state, tfvars and saved plans are ignored. Keep a secure backup of local Terraform state
once resources are provisioned; losing state does not delete the resources but prevents
safe continued management. Do not reuse or copy Chronologs' state.

Both the VPS and backup bucket use `prevent_destroy`; the VPS also enables Hetzner's
API delete/rebuild protection. Deliberate replacement requires reviewing the data and
explicitly changing these protections. Server disk holds the Docker SQLite volume;
VPS snapshots are additional protection, not a substitute for verified Litestream backups.

## After a separately authorized apply

Read the outputs and use them in the existing Kamal setup:

```sh
export FLUENTLY_SERVER="$(terraform -chdir=terraform output -raw app_ip)"
export LITESTREAM_BUCKET="$(terraform -chdir=terraform output -raw backup_bucket_name)"
```

Point the application's DNS A record at `app_ip`, set `PHX_HOST`, and follow
[the deployment guide](../docs/deployment.md). Terraform does not install Docker,
run Kamal, configure DNS, deploy the app, or create S3 access keys. Supply Litestream
credentials separately, preferably scoped to the backup bucket. Kamal prepares the
shared volume permissions and runs the backup accessory and application.

# Setup Prerequisites

This guide walks through the prerequisites needed before deploying the multicluster broadcaster application.

## Required Accounts & Tools

1. **Google Cloud Platform account** with billing enabled
2. **GitHub account** with a forked copy of this repository
3. **Domain name** that you control (for DNS configuration)
4. **Local tools installed:**
   - `gcloud` CLI (authenticated)
   - `terraform` (v1.0+)
   - `kubectl`

## Google Cloud Setup

### 1. Create GCP Project
```bash
# Create a new project (or use existing)
gcloud projects create your-project-id --name="Your Project Name Here"

# Set as default project
gcloud config set project your-project-id

# Enable billing (required for GKE and other services)
# Do this in the Google Cloud Console: Billing → Link a billing account
```

### 2. Get Project Information
```bash
# Get your project ID (if you don't remember it)
gcloud config get-value project

# Get your project number (needed for Terraform)
gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"
```

### 3. Enable Required APIs
```bash
# The following APIs will be enabled automatically by Terraform, but you can enable them manually:
gcloud services enable container.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

## GitHub Setup

### 1. Fork This Repository

1. Go to the GitHub repository page
2. Click "Fork" to create your own copy
3. Clone your forked repository locally

Or, just clone the repo and create a new one if you don't want to fork.

### 2. Install Cloud Build GitHub App
1. Go to https://github.com/marketplace/google-cloud-build
2. Click "Set up a plan" → "Install it for free"
3. Choose your account/organization
4. Select "Only select repositories" and choose your forked repo
5. Complete the installation

### 3. Create GitHub OAuth Token Secret

1. Generate a Personal Access Token:
   - Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
   - Click "Generate new token (classic)"
   - Set expiration to "No expiration"
   - Select scopes: `repo`, `read:user`, and `read:org` (if installing in an organization)
   - Copy the generated token

2. Store in Google Secret Manager:

   ```bash
   # Create a secret in Secret Manager
   echo -n "your-github-token-here" | gcloud secrets create github-oauth-token --data-file=-
   
   # Note the secret ID (usually just "github-oauth-token") for your terraform.tfvars
   ```

### 4. Get GitHub App Installation ID

1. Go to https://github.com/settings/installations
2. Find "Google Cloud Build" app
3. Click "Configure"
4. Look at the URL: `https://github.com/settings/installations/12345678`
5. The number `12345678` is your installation ID

## Domain Setup

You'll need a domain name that you control. The application will be accessible at `broadcaster.yourdomain.com`.

**Note:** You don't need to configure DNS records manually - Terraform will create a Cloud DNS zone and provide name servers for you to configure at your domain registrar.

## Terraform Configuration

### 1. Copy Example Configuration

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### 2. Fill in Your Values

Edit `terraform.tfvars` with your specific information:

```hcl
# Your GCP project ID
project_id = "your-project-id-here"

# Your GCP project number
project_number = "123456789012"

# Your domain name (without subdomain)
domain = "yourdomain.com"

# GitHub App installation ID
github_app_installation_id = "12345678"

# GitHub repository configuration
github_oauth_secret_id = "github-oauth-token"  # Secret Manager secret ID
github_repo_owner      = "your-github-username"
github_repo_name       = "multicluster-broadcaster-swm-l7mp"
```

## Verification

Before proceeding with deployment, verify your setup:

```bash
# Verify gcloud authentication and project
gcloud auth list
gcloud config get-value project

# Verify project number
gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)"

# Verify secret exists
gcloud secrets describe github-oauth-token

# Verify Terraform configuration
cd terraform
terraform validate
```

## Next Steps

Once you have completed all prerequisites, you can proceed with:

1. **Deploy infrastructure:** `terraform apply`
2. **Commit and push** to trigger your first deployment

For detailed deployment instructions, see the main [README.md](../README.md) or [secrets-setup.md](./secrets-setup.md). 
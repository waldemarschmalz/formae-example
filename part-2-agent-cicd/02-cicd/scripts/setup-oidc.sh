#!/usr/bin/env bash
# Sets up OIDC federation between GitHub Actions and Azure.
# Run once before using the CI/CD workflows.
# Usage: ./setup-oidc.sh --repo owner/repo --subscription <id>

set -euo pipefail

usage() {
  echo "Usage: $0 --repo <owner/repo> --subscription <subscription-id> [--app-name <name>]"
  exit 1
}

APP_NAME="formae-cicd-ghactions"
REPO=""
SUBSCRIPTION_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)           REPO="$2";            shift 2 ;;
    --subscription)   SUBSCRIPTION_ID="$2"; shift 2 ;;
    --app-name)       APP_NAME="$2";        shift 2 ;;
    *)                usage ;;
  esac
done

[[ -z "$REPO" || -z "$SUBSCRIPTION_ID" ]] && usage

echo "Creating app registration: $APP_NAME"
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID" >/dev/null

echo "Adding federated credential for push to main..."
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"github-push-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:${REPO}:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}" >/dev/null

echo "Adding federated credential for pull requests..."
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"github-pull-request\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:${REPO}:pull_request\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}" >/dev/null

echo "Granting Contributor on subscription $SUBSCRIPTION_ID..."
az role assignment create \
  --assignee "$APP_ID" \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID" >/dev/null

TENANT_ID=$(az account show --query tenantId -o tsv)

echo ""
echo "Done. Add these as GitHub Actions secrets:"
echo ""
echo "  AZURE_CLIENT_ID:       $APP_ID"
echo "  AZURE_TENANT_ID:       $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "  FORMAE_API_PASSWORD:   <the password set during agent install>"

#!/bin/bash
# plan-bwrap.sh
#
# Custom Atlantis plan step: runs terraform plan inside a bwrap sandbox where
# the read-write SA token is replaced with a short-lived readonly token.
#
# The bwrap sandbox is a new user+mount namespace where:
#   - The entire filesystem is bind-mounted read-only.
#   - The working directory ($DIR) is re-bind-mounted read-write (plan output).
#   - The SA token path is shadowed with a fresh readonly token.
#   - The kubeconfig is shadowed with one that references the readonly token.
#
# Any provider or module code that runs during terraform plan physically cannot
# read the rw SA token — it has been replaced in the sandbox's mount namespace.
#
# The init step (terraform init) runs before this script, outside the sandbox,
# using the main SA credentials. Provider downloads don't touch the k8s API.
#
# Environment variables supplied by Atlantis:
#   DIR                        - absolute path to the project directory
#   PLANFILE                   - absolute path where plan output must be written
#   WORKSPACE                  - terraform workspace
#   ATLANTIS_TERRAFORM_VERSION - terraform version suffix (e.g. "1.14.0")
#
# Environment variable injected by main.tf:
#   ATLANTIS_INSTANCE - e.g. "readonly-bwrap"

set -euo pipefail

: "${ATLANTIS_INSTANCE:?ATLANTIS_INSTANCE env var not set (should be injected by main.tf deployment)}"
: "${DIR:?}"
: "${PLANFILE:?}"
: "${WORKSPACE:?}"
: "${ATLANTIS_TERRAFORM_VERSION:?}"

READONLY_SA="atlantis-${ATLANTIS_INSTANCE}-readonly"
SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
SA_CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
SA_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

TF_BIN="/root/.atlantis/bin/terraform${ATLANTIS_TERRAFORM_VERSION}"
if [ ! -x "$TF_BIN" ]; then
  echo "ERROR: terraform binary not found at $TF_BIN"
  echo "Atlantis should have pre-downloaded it before running this step."
  exit 1
fi

# ---- Mint a short-lived token for the readonly SA ---------------------------
#
# Uses the Kubernetes TokenRequest API directly via curl so we don't need
# kubectl. The main SA has a Role granting create on serviceaccounts/token
# scoped to the readonly SA only (see main.tf: mint_readonly_token).

echo "==> Minting readonly token for SA '${READONLY_SA}'"

READONLY_TOKEN=$(curl -sf \
  --cacert "$SA_CA_PATH" \
  -H "Authorization: Bearer $(cat "$SA_TOKEN_PATH")" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"apiVersion":"authentication.k8s.io/v1","kind":"TokenRequest","spec":{"expirationSeconds":900}}' \
  "https://kubernetes.default.svc/api/v1/namespaces/${SA_NAMESPACE}/serviceaccounts/${READONLY_SA}/token" \
  | jq -r '.status.token')

if [ -z "$READONLY_TOKEN" ]; then
  echo "ERROR: Failed to mint readonly token for SA '${READONLY_SA}'"
  exit 1
fi

echo "    Token minted (expires in 15m)"

# ---- Prepare credential files -----------------------------------------------
#
# These host-side temp files are bind-mounted into the bwrap sandbox at the
# SA token and kubeconfig paths, shadowing the rw credentials.
# bwrap resolves bind-mount sources from the host namespace, so $SANDBOX_TMP
# (used for the writable /tmp inside the sandbox) and $CREDS_TMP are accessible
# as source paths even after bwrap remounts /tmp inside the sandbox.

CREDS_TMP=$(mktemp -d)
SANDBOX_TMP=$(mktemp -d)
trap 'rm -rf "$CREDS_TMP" "$SANDBOX_TMP"' EXIT

# Readonly SA token (replaces the pod's rw token inside the sandbox)
printf '%s' "$READONLY_TOKEN" > "$CREDS_TMP/token"

# Kubeconfig using the readonly token (replaces ~/.kube/config inside the sandbox)
# References $SA_CA_PATH which is accessible in the sandbox via --ro-bind / /
#
# Note: In a production setup, a kubeconfig might not be needed. We need it here to be able to use a "kind-atlantis-demo" context in the kubernetes provider. That's a demo specific requirement.
cat > "$CREDS_TMP/kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: ${SA_CA_PATH}
    server: https://kubernetes.default.svc
  name: in-cluster
contexts:
- context:
    cluster: in-cluster
    user: readonly
  name: kind-atlantis-demo
current-context: kind-atlantis-demo
users:
- name: readonly
  user:
    token: ${READONLY_TOKEN}
EOF

# ---- Workspace selection (outside sandbox — touches only state backend) -----

cd "$DIR"

if [ "$WORKSPACE" != "default" ]; then
  echo "==> terraform workspace select ${WORKSPACE}"
  "$TF_BIN" workspace select "$WORKSPACE" 2>/dev/null \
    || "$TF_BIN" workspace new "$WORKSPACE"
fi

# ---- Run terraform plan inside bwrap ----------------------------------------
#
# On AWS/IRSA, the pod also has AWS_WEB_IDENTITY_TOKEN_FILE pointing to the
# rw SA's projected token (a separate path from $SA_TOKEN_PATH). The AWS SDK
# uses that file to call sts:AssumeRoleWithWebIdentity, so it must be shadowed
# too — otherwise a provider could still assume the rw IAM role. Example:
#   --bind "$CREDS_TMP/token" "$AWS_WEB_IDENTITY_TOKEN_FILE" \
# AWS_ROLE_ARN also needs to be overridden (it's an env var, not a file):
#   --setenv AWS_ROLE_ARN "arn:aws:iam::ACCOUNT:role/readonly-role" \

echo "==> terraform plan (bwrap sandbox, SA: ${READONLY_SA})"
echo ""

bwrap \
  --ro-bind / / \
  --dev /dev \
  --proc /proc \
  --bind "$SANDBOX_TMP" /tmp \
  --bind "$DIR" "$DIR" \
  --bind "$CREDS_TMP/token" "$SA_TOKEN_PATH" \
  --bind "$CREDS_TMP/kubeconfig" /root/.kube/config \
  --setenv KUBECONFIG /root/.kube/config \
  -- "$TF_BIN" plan -input=false -no-color -out="$PLANFILE"

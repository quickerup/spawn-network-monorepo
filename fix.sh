#!/usr/bin/env bash
set -e

if [ ! -f "package.json" ] || [ ! -d "apps" ]; then
  echo "❌ Run this from the root of spawn-network-monorepo."
  exit 1
fi

command -v git >/dev/null || { echo "❌ git not found."; exit 1; }
command -v curl >/dev/null || { echo "❌ curl not found."; exit 1; }
command -v python3 >/dev/null || { echo "❌ python3 not found."; exit 1; }

# ---------------------------------------------------------------------------
# Gather inputs
# ---------------------------------------------------------------------------
read -rp "GitHub username: " GH_USER
read -rp "Repo name [spawn-network-monorepo]: " REPO_NAME
REPO_NAME="${REPO_NAME:-spawn-network-monorepo}"
read -rp "Visibility (private/public) [private]: " REPO_VIS
REPO_VIS="${REPO_VIS:-private}"

echo -n "GitHub PAT (input hidden): "
read -rs GH_PAT
echo
echo -n "Cloudflare API Token (input hidden): "
read -rs CF_TOKEN
echo

cleanup() { unset GH_PAT CF_TOKEN; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Verify the PAT works
# ---------------------------------------------------------------------------
echo "Verifying PAT..."
WHOAMI=$(curl -s -H "Authorization: Bearer $GH_PAT" -H "Accept: application/vnd.github+json" \
  https://api.github.com/user | python3 -c "import sys,json; print(json.load(sys.stdin).get('login',''))")

if [ -z "$WHOAMI" ]; then
  echo "❌ PAT didn't authenticate. Check the token and its scopes (needs 'repo', or fine-grained Administration + Secrets write)."
  exit 1
fi
echo "  ✓ Authenticated as $WHOAMI"

# ---------------------------------------------------------------------------
# Create the repo (skip if it already exists)
# ---------------------------------------------------------------------------
EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$GH_USER/$REPO_NAME")

if [ "$EXISTS" = "200" ]; then
  echo "  ⚠ Repo $GH_USER/$REPO_NAME already exists — skipping creation, will push to it."
else
  echo "Creating repo $GH_USER/$REPO_NAME ($REPO_VIS)..."
  PRIVATE_BOOL="true"
  [ "$REPO_VIS" = "public" ] && PRIVATE_BOOL="false"

  CREATE_STATUS=$(curl -s -o /tmp/gh_create_resp.json -w "%{http_code}" \
    -H "Authorization: Bearer $GH_PAT" -H "Accept: application/vnd.github+json" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO_NAME\",\"private\":$PRIVATE_BOOL,\"auto_init\":false}")

  if [ "$CREATE_STATUS" != "201" ]; then
    echo "❌ Repo creation failed (HTTP $CREATE_STATUS):"
    cat /tmp/gh_create_resp.json
    exit 1
  fi
  echo "  ✓ Repo created"
fi

# ---------------------------------------------------------------------------
# Init git + push
# ---------------------------------------------------------------------------
if [ ! -d ".git" ]; then
  git init -q
  git branch -M main
fi

git add -A
git commit -q -m "Initial commit: spawn-network-monorepo" || echo "  (nothing new to commit)"

PUSH_URL="https://$GH_USER:$GH_PAT@github.com/$GH_USER/$REPO_NAME.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$PUSH_URL"

echo "Pushing to GitHub..."
git push -u origin main -q

# Reset remote to a clean URL so the PAT isn't left sitting in .git/config
git remote set-url origin "https://github.com/$GH_USER/$REPO_NAME.git"
echo "  ✓ Pushed. Remote URL cleaned of credentials."

# ---------------------------------------------------------------------------
# Set the CLOUDFLARE_API_TOKEN repo secret
# ---------------------------------------------------------------------------
echo "Fetching repo public key for secret encryption..."
KEY_JSON=$(curl -s -H "Authorization: Bearer $GH_PAT" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GH_USER/$REPO_NAME/actions/secrets/public-key")

KEY_ID=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['key_id'])")
PUBLIC_KEY=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

# Encrypting natively via ctypes and the system libsodium to avoid pip/pynacl errors
ENCRYPTED=$(printf '%s' "$CF_TOKEN" | python3 - "$PUBLIC_KEY" << 'EOF'
import sys, base64, ctypes, ctypes.util, os

lib_path = ctypes.util.find_library('sodium') or ctypes.util.find_library('libsodium')
if not lib_path:
    # Explicit fallbacks for Termux and common Unix environments
    fallbacks = [
        '/data/data/com.termux/files/usr/lib/libsodium.so',
        '/usr/lib/libsodium.so',
        '/usr/lib/x86_64-linux-gnu/libsodium.so',
        '/usr/local/lib/libsodium.dylib'
    ]
    for p in fallbacks:
        if os.path.exists(p):
            lib_path = p
            break

if not lib_path:
    print("❌ libsodium not found. Install it via OS package manager (e.g., 'pkg install libsodium').", file=sys.stderr)
    sys.exit(1)

try:
    sodium = ctypes.cdll.LoadLibrary(lib_path)
except Exception as e:
    print("❌ Failed to load libsodium: " + str(e), file=sys.stderr)
    sys.exit(1)

# Configure function signature for crypto_box_seal
sodium.crypto_box_seal.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p]
sodium.crypto_box_seal.restype = ctypes.c_int

public_key = base64.b64decode(sys.argv[1])
secret_value = sys.stdin.buffer.read()

# libsodium crypto_box_SEALBYTES is exactly 48 bytes
out_len = len(secret_value) + 48
ciphertext = ctypes.create_string_buffer(out_len)

if sodium.crypto_box_seal(ciphertext, secret_value, len(secret_value), public_key) != 0:
    print("❌ Encryption failed inside libsodium", file=sys.stderr)
    sys.exit(1)

print(base64.b64encode(ciphertext.raw).decode('utf-8'))
EOF
)

# Ensure encryption didn't fail before proceeding
if [ -z "$ENCRYPTED" ]; then
    echo "❌ Failed to encrypt token. Exiting."
    exit 1
fi

echo "Setting CLOUDFLARE_API_TOKEN secret..."
SECRET_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT -H "Authorization: Bearer $GH_PAT" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GH_USER/$REPO_NAME/actions/secrets/CLOUDFLARE_API_TOKEN" \
  -d "{\"encrypted_value\":\"$ENCRYPTED\",\"key_id\":\"$KEY_ID\"}")

if [ "$SECRET_STATUS" = "201" ] || [ "$SECRET_STATUS" = "204" ]; then
  echo "  ✓ CLOUDFLARE_API_TOKEN secret set"
else
  echo "  ❌ Failed to set secret (HTTP $SECRET_STATUS)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Standardize workflows to use CLOUDFLARE_API_TOKEN
# ---------------------------------------------------------------------------
if grep -rl "CF_API_TOKEN" .github/workflows/ >/dev/null 2>&1; then
  echo "Standardizing secret name across workflows..."
  grep -rl "CF_API_TOKEN" .github/workflows/ | xargs sed -i.bak 's/CF_API_TOKEN/CLOUDFLARE_API_TOKEN/g'
  find .github/workflows -name "*.bak" -delete
  git add .github/workflows
  git commit -q -m "chore: standardize secret name to CLOUDFLARE_API_TOKEN" || true
  git push -q
  echo "  ✓ Workflows updated and pushed"
fi

echo ""
echo "✅ Done."
echo "   Repo:    https://github.com/$GH_USER/$REPO_NAME"
echo "   Actions: https://github.com/$GH_USER/$REPO_NAME/actions"
echo ""
echo "Next: trigger 'Deploy Registry Service' manually (Actions tab → Run workflow)"
echo "to confirm it deploys cleanly from a real Linux runner."

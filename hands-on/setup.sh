#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# IAM 脱出ゲーム — 金庫（IAM ポリシー）と 5 つの鍵（拒否）を仕込む。
# 2026 年 10 月時点、authorization ID が付くのは主に IAM の API なので、金庫も IAM のリソースにしている。
# IAM access troubleshooter はプレビュー中 us-east-1 のみ。IAM はグローバルサービスだが、CloudShell を us-east-1 で
# 開いていれば拒否の記録も us-east-1 に残る。
readonly PROJECT_NAME="aws-deepcuts"
readonly REGION="us-east-1"
readonly ROLE_NAME="${PROJECT_NAME}-detective"
readonly BOUNDARY_NAME="${PROJECT_NAME}-detective-boundary"
readonly LICENSE_NAME="${PROJECT_NAME}-detective-license"
readonly SEALED_NAME="${PROJECT_NAME}-sealed"
readonly VAULT_NAME="${PROJECT_NAME}-vault"
readonly CURSE_POLICY_NAME="${PROJECT_NAME}-cursed"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM 脱出ゲーム セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── [1/6] 前提チェック ─────────────────────────────────────────
echo "[1/6] 前提を確認..."
if [[ -f "${RESOURCE_FILE}" ]]; then
  echo "❌ Error: ${RESOURCE_FILE} が既に存在します。前回の環境が残っています。" >&2
  echo "   先に bash ./cleanup.sh を実行してください。" >&2
  exit 1
fi
if [[ "${DEEPCUTS_DETECTIVE:-}" == "1" ]]; then
  echo "❌ Error: 探偵のままです。先に source ./admin.sh で自分に戻ってください。" >&2
  exit 1
fi
if ! aws iam-toolbox get-request-authorization-details --generate-cli-skeleton input >/dev/null 2>&1; then
  echo "❌ Error: この AWS CLI は iam-toolbox コマンドに対応していません。AWS CLI v2 を最新版に更新してください。" >&2
  exit 1
fi
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || {
  echo "❌ Error: AWS 認証情報が取得できません。AWS CLI の設定を確認してください。" >&2
  exit 1
}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}" != "us-east-1" ]]; then
  echo "⚠️  CloudShell のリージョンが us-east-1 ではないようです（${AWS_REGION:-${AWS_DEFAULT_REGION:-}}）。"
  echo "   Access Troubleshooter はプレビュー中 us-east-1 のみなので、us-east-1 の CloudShell で実行してください。"
fi
echo "  あなた: ${CALLER_ARN}"
echo "  アカウント: ${ACCOUNT_ID} / リージョン: ${REGION}"
echo ""

VAULT_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${VAULT_NAME}"

# ─── [2/6] 金庫（修了証を説明文に刻んだ IAM ポリシー） ──────────
echo "[2/6] 金庫を作成（IAM ポリシー ${VAULT_NAME}。説明文に修了証）..."
CERTIFICATE="[修了証] IAM 脱出ゲーム (AWS Deep Cuts) - あなたは 5 つの鍵 (明示的 Deny x2, 暗黙の拒否, 条件キー, アクセス許可の境界) を authorization ID と IAM Access Troubleshooter で解き明かし, 金庫を開けました. 発行: アカウント ${ACCOUNT_ID} / $(date -u +%Y-%m-%d). 次の一歩: 本物の AccessDenied に出会ったら, まずエラーメッセージの中の authorization ID を探してください. 真犯人は, もう隠れられません."
aws iam create-policy --policy-name "${VAULT_NAME}" \
  --description "${CERTIFICATE}" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "ThisPolicyIsJustAVault",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*"
    }]
  }' >/dev/null
echo "  ${VAULT_ARN}"
echo ""

# ─── [3/6] 鍵 4: アクセス許可の境界（iam:GetPolicy が無い） ──────
echo "[3/6] アクセス許可の境界ポリシーを作成（鍵 4）..."
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${BOUNDARY_NAME}"
aws iam create-policy --policy-name "${BOUNDARY_NAME}" \
  --description "AWS Deep Cuts IAM escape game: permissions boundary for the detective (no iam:GetPolicy)" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "DetectiveBoundary",
      "Effect": "Allow",
      "Action": ["iam:ListPolicies", "sts:GetCallerIdentity"],
      "Resource": "*"
    }]
  }' >/dev/null
echo "  ${BOUNDARY_ARN}"
echo ""

# ─── [4/6] 探偵ロール（鍵 1: 呪いと封印、鍵 3: 階級タグ） ────────
echo "[4/6] 探偵ロールを作成（鍵 1・鍵 3）..."
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
aws iam create-role --role-name "${ROLE_NAME}" \
  --description "AWS Deep Cuts IAM escape game: the detective who tries to open the vault" \
  --permissions-boundary "${BOUNDARY_ARN}" \
  --tags "Key=Project,Value=${PROJECT_NAME}" "Key=clearance,Value=rookie" \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\"},
      \"Action\": [\"sts:AssumeRole\", \"sts:TagSession\"]
    }]
  }" >/dev/null
# 鍵 1a: 探偵自身に掛けられた「呪い」（インラインポリシーの明示的 Deny）
aws iam put-role-policy --role-name "${ROLE_NAME}" --policy-name "${CURSE_POLICY_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"Cursed\",
      \"Effect\": \"Deny\",
      \"Action\": \"iam:GetPolicy\",
      \"Resource\": \"${VAULT_ARN}\"
    }]
  }"
# 鍵 1b: 金庫の「封印」（管理ポリシーの明示的 Deny。探偵にアタッチ）
SEALED_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${SEALED_NAME}"
aws iam create-policy --policy-name "${SEALED_NAME}" \
  --description "AWS Deep Cuts IAM escape game: the seal on the vault (explicit deny)" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"VaultSealed\",
      \"Effect\": \"Deny\",
      \"Action\": \"iam:GetPolicy\",
      \"Resource\": \"${VAULT_ARN}\"
    }]
  }" >/dev/null
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${SEALED_ARN}"
echo "  ${ROLE_ARN}（タグ clearance=rookie、呪い ${CURSE_POLICY_NAME}、封印 ${SEALED_NAME}）"
echo ""

# ─── [5/6] 探偵免許（鍵 2: まだ付いていない、鍵 3: 条件付き） ─────
echo "[5/6] 探偵免許（管理ポリシー、未アタッチ）を作成（鍵 2・鍵 3）..."
LICENSE_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${LICENSE_NAME}"
aws iam create-policy --policy-name "${LICENSE_NAME}" \
  --description "AWS Deep Cuts IAM escape game: detective license (opening the vault needs clearance=top-secret)" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"LookAround\",
        \"Effect\": \"Allow\",
        \"Action\": \"iam:ListPolicies\",
        \"Resource\": \"*\"
      },
      {
        \"Sid\": \"OpenVaultWithClearance\",
        \"Effect\": \"Allow\",
        \"Action\": \"iam:GetPolicy\",
        \"Resource\": \"${VAULT_ARN}\",
        \"Condition\": {\"StringEquals\": {\"aws:PrincipalTag/clearance\": \"top-secret\"}}
      }
    ]
  }" >/dev/null
echo "  ${LICENSE_ARN}"
echo ""

# ─── [6/6] 保存と伝播待ち ──────────────────────────────────────
echo "[6/6] リソース情報を保存し、IAM の伝播を待機（10 秒）..."
cat > "${RESOURCE_FILE}" <<EOF
# AWS Deep Cuts IAM 脱出ゲーム - リソース情報（setup.sh が自動生成）
REGION="${REGION}"
ACCOUNT_ID="${ACCOUNT_ID}"
ROLE_NAME="${ROLE_NAME}"
ROLE_ARN="${ROLE_ARN}"
VAULT_NAME="${VAULT_NAME}"
VAULT_ARN="${VAULT_ARN}"
BOUNDARY_ARN="${BOUNDARY_ARN}"
LICENSE_ARN="${LICENSE_ARN}"
SEALED_ARN="${SEALED_ARN}"
CURSE_POLICY_NAME="${CURSE_POLICY_NAME}"
EOF
sleep 10
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップが完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "金庫: ${VAULT_ARN}"
echo "探偵: ${ROLE_ARN}"
echo ""
echo "次のステップ: source ./detective.sh で探偵になり、金庫を開けてみてください。"
echo "  aws iam get-policy --policy-arn ${VAULT_ARN} --query Policy.Description --output text"

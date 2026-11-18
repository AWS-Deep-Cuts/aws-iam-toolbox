#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# AWS Deep Cuts - IAM Access Troubleshooter ハンズオンの事前準備
# ハンズオン用ロールと、読み取りを拒否する 4 種類の設定（ステージ 1〜4）を作成します。
#   修了証のポリシー        aws-deepcuts-certificate       説明文（Description）に修了証。iam:GetPolicy で読み取る対象
#   ハンズオン用ロール      aws-deepcuts-handson-role      タグ team=dev。アクセス許可の境界に aws-deepcuts-boundary
#   ステージ 1              aws-deepcuts-inline-deny       ロールのインラインポリシー。修了証のポリシーへの iam:GetPolicy を Deny
#                           aws-deepcuts-managed-deny      ロールにアタッチした管理ポリシー。同じく Deny
#   ステージ 2・3           aws-deepcuts-read-certificate  iam:GetPolicy を Allow する管理ポリシー。条件 team=security。まだアタッチしない
#   ステージ 4              aws-deepcuts-boundary          アクセス許可の境界。iam:GetPolicy を含まない
# authorization ID が付くのは、2026 年 10 月時点では主に IAM の API であるため、読み取る対象も IAM のポリシーにしている。
# IAM Access Troubleshooter はプレビュー中で us-east-1 だけで提供されているため、us-east-1 の CloudShell で実行する。

readonly PROJECT_NAME="aws-deepcuts"
readonly REGION="us-east-1"
readonly ROLE_NAME="${PROJECT_NAME}-handson-role"
readonly CERT_NAME="${PROJECT_NAME}-certificate"
readonly INLINE_DENY_NAME="${PROJECT_NAME}-inline-deny"
readonly MANAGED_DENY_NAME="${PROJECT_NAME}-managed-deny"
readonly READ_POLICY_NAME="${PROJECT_NAME}-read-certificate"
readonly BOUNDARY_NAME="${PROJECT_NAME}-boundary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Access Troubleshooter 事前準備"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── [1/6] 前提の確認 ─────────────────────────────────────────
echo "[1/6] 前提を確認..."
if [[ -f "${RESOURCE_FILE}" ]]; then
  echo "❌ Error: ${RESOURCE_FILE} が既に存在します。前回の環境が残っています。" >&2
  echo "   先に bash ./cleanup.sh を実行してください。" >&2
  exit 1
fi
if [[ "${DEEPCUTS_HANDSON_ROLE:-}" == "1" ]]; then
  echo "❌ Error: ハンズオン用ロールに切り替えたままです。先に source ./switch-back.sh を実行してください。" >&2
  exit 1
fi
# iam-toolbox コマンドは、README の手順 3 の「CLI で評価の詳細を取得する方法」だけで使う。対応していなくても続ける
if ! aws iam-toolbox get-request-authorization-details --generate-cli-skeleton input >/dev/null 2>&1; then
  echo "⚠️  この AWS CLI は iam-toolbox コマンドに対応していません（現在: $(aws --version 2>&1 | cut -d' ' -f1)）。"
  echo "   ハンズオンはこのまま進められます。手順 3 の「CLI で評価の詳細を取得する方法」を試す場合だけ、README の手順で更新してください。"
fi
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || {
  echo "❌ Error: AWS の認証情報を取得できません。CloudShell で実行しているか確認してください。" >&2
  exit 1
}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
case "${CALLER_ARN}" in
  *:root)
    echo "❌ Error: ルートユーザーで実行しています。ルートユーザーはロールに切り替えられないため、このハンズオンを実施できません。" >&2
    echo "   IAM ユーザーまたは IAM Identity Center のユーザーでサインインしてから実行してください。" >&2
    exit 1 ;;
esac
if [[ "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}" != "us-east-1" ]]; then
  echo "⚠️  CloudShell のリージョンが us-east-1 ではありません（${AWS_REGION:-${AWS_DEFAULT_REGION:-}}）。"
  echo "   Access Troubleshooter はプレビュー中で us-east-1 だけで提供されているため、us-east-1 の CloudShell で実行してください。"
fi
echo "  あなた（管理者）: ${CALLER_ARN}"
echo "  アカウント: ${ACCOUNT_ID} / リージョン: ${REGION}"

CERT_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${CERT_NAME}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
MANAGED_DENY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${MANAGED_DENY_NAME}"
READ_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${READ_POLICY_NAME}"
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${BOUNDARY_NAME}"

# 名前は作成前に決まっているため、先にリソース情報を保存する（途中で失敗しても cleanup.sh で削除できる）
cat > "${RESOURCE_FILE}" <<EOF
# AWS Deep Cuts IAM Access Troubleshooter - リソース情報（setup.sh が作成）
REGION="${REGION}"
ACCOUNT_ID="${ACCOUNT_ID}"
ROLE_NAME="${ROLE_NAME}"
ROLE_ARN="${ROLE_ARN}"
CERT_NAME="${CERT_NAME}"
CERT_ARN="${CERT_ARN}"
INLINE_DENY_NAME="${INLINE_DENY_NAME}"
MANAGED_DENY_ARN="${MANAGED_DENY_ARN}"
READ_POLICY_ARN="${READ_POLICY_ARN}"
BOUNDARY_ARN="${BOUNDARY_ARN}"
EOF
# 前回の残りがあれば止める（resource-ids.env は上で保存したため、cleanup.sh でまとめて削除できる）
for arn in "${CERT_ARN}" "${MANAGED_DENY_ARN}" "${READ_POLICY_ARN}" "${BOUNDARY_ARN}"; do
  if aws iam get-policy --policy-arn "${arn}" >/dev/null 2>&1; then
    echo "❌ Error: ${arn} が既に存在します。前回の環境が残っています。" >&2
    echo "   bash ./cleanup.sh を実行してから、もう一度 bash ./setup.sh を実行してください。" >&2
    exit 1
  fi
done
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "❌ Error: ロール ${ROLE_NAME} が既に存在します。前回の環境が残っています。" >&2
  echo "   bash ./cleanup.sh を実行してから、もう一度 bash ./setup.sh を実行してください。" >&2
  exit 1
fi
echo ""

# ─── [2/6] 修了証のポリシー ───────────────────────────────────
echo "[2/6] 修了証のポリシーを作成（${CERT_NAME}）..."
CERT_TEXT="[修了証] AWS Deep Cuts IAM Access Troubleshooter ハンズオン - あなたは、明示的な拒否・許可の不足・条件の不一致・アクセス許可の境界による 4 種類の拒否の原因を、authorization ID と IAM Access Troubleshooter で特定し、このポリシーの説明文を読み取りました。発行: アカウント ${ACCOUNT_ID} / $(date -u +%Y-%m-%d)。AccessDenied のエラーが出たら、まずメッセージの最後にある authorization ID を探してください。"
CERT_TEXT_ASCII="[Certificate] AWS Deep Cuts IAM Access Troubleshooter hands-on - You identified the causes of four kinds of denials (explicit deny, missing allow, unmet condition, permissions boundary) with authorization IDs and IAM Access Troubleshooter, and read this policy description. Issued: account ${ACCOUNT_ID} / $(date -u +%Y-%m-%d). When you see AccessDenied, look for the authorization ID at the end of the message first."
# このポリシーはどこにもアタッチしない。説明文を読み取る対象として使うだけなので、本文は何も許可しない
CERT_DOCUMENT='{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "NotUsedForAccessControl",
    "Effect": "Deny",
    "Action": "*",
    "Resource": "*"
  }]
}'
ERR_LOG="${SCRIPT_DIR}/.setup-error.log"
if ! aws iam create-policy --policy-name "${CERT_NAME}" --description "${CERT_TEXT}" \
      --tags "Key=Project,Value=${PROJECT_NAME}" --policy-document "${CERT_DOCUMENT}" >/dev/null 2>"${ERR_LOG}"; then
  if grep -qiE "ValidationError|Invalid|pattern" "${ERR_LOG}"; then
    echo "  日本語の説明文が受け付けられなかったため、英語の修了証で作成します。"
    aws iam create-policy --policy-name "${CERT_NAME}" --description "${CERT_TEXT_ASCII}" \
      --tags "Key=Project,Value=${PROJECT_NAME}" --policy-document "${CERT_DOCUMENT}" >/dev/null
  else
    cat "${ERR_LOG}" >&2
    rm -f "${ERR_LOG}"
    exit 1
  fi
fi
rm -f "${ERR_LOG}"
echo "  作成: ${CERT_ARN}"
echo ""

# ─── [3/6] ステージ 4: アクセス許可の境界 ───────────────────────
echo "[3/6] アクセス許可の境界を作成（${BOUNDARY_NAME}。iam:GetPolicy を含まない）..."
aws iam create-policy --policy-name "${BOUNDARY_NAME}" \
  --description "AWS Deep Cuts IAM Access Troubleshooter hands-on: permissions boundary without iam:GetPolicy" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "BoundaryAllowedActions",
      "Effect": "Allow",
      "Action": ["iam:ListPolicies", "sts:GetCallerIdentity"],
      "Resource": "*"
    }]
  }' >/dev/null
echo "  作成: ${BOUNDARY_ARN}"
echo ""

# ─── [4/6] ハンズオン用ロールと、ステージ 1 の Deny ─────────────
echo "[4/6] ハンズオン用ロールを作成（${ROLE_NAME}。タグ team=dev、境界 ${BOUNDARY_NAME}）..."
aws iam create-role --role-name "${ROLE_NAME}" \
  --description "AWS Deep Cuts IAM Access Troubleshooter hands-on role" \
  --permissions-boundary "${BOUNDARY_ARN}" \
  --tags "Key=Project,Value=${PROJECT_NAME}" "Key=team,Value=dev" \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\"},
      \"Action\": [\"sts:AssumeRole\", \"sts:TagSession\"]
    }]
  }" >/dev/null
echo "  作成: ${ROLE_ARN}"
# ステージ 1（その 1）: ロールに埋め込むインラインポリシーの Deny
aws iam put-role-policy --role-name "${ROLE_NAME}" --policy-name "${INLINE_DENY_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyReadCertificateInline\",
      \"Effect\": \"Deny\",
      \"Action\": \"iam:GetPolicy\",
      \"Resource\": \"${CERT_ARN}\"
    }]
  }"
echo "  インラインポリシーを追加: ${INLINE_DENY_NAME}"
# ステージ 1（その 2）: ロールにアタッチする管理ポリシーの Deny
aws iam create-policy --policy-name "${MANAGED_DENY_NAME}" \
  --description "AWS Deep Cuts IAM Access Troubleshooter hands-on: explicit deny on reading the certificate policy" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyReadCertificate\",
      \"Effect\": \"Deny\",
      \"Action\": \"iam:GetPolicy\",
      \"Resource\": \"${CERT_ARN}\"
    }]
  }" >/dev/null
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${MANAGED_DENY_ARN}"
echo "  管理ポリシーを作成してアタッチ: ${MANAGED_DENY_NAME}"
echo ""

# ─── [5/6] ステージ 2・3: 条件付きで許可する管理ポリシー ─────────
echo "[5/6] 読み取りを許可する管理ポリシーを作成（${READ_POLICY_NAME}。まだアタッチしない）..."
aws iam create-policy --policy-name "${READ_POLICY_NAME}" \
  --description "AWS Deep Cuts IAM Access Troubleshooter hands-on: allow reading the certificate policy when the principal tag team is security" \
  --tags "Key=Project,Value=${PROJECT_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"AllowReadCertificateForSecurityTeam\",
      \"Effect\": \"Allow\",
      \"Action\": \"iam:GetPolicy\",
      \"Resource\": \"${CERT_ARN}\",
      \"Condition\": {\"StringEquals\": {\"aws:PrincipalTag/team\": \"security\"}}
    }]
  }" >/dev/null
echo "  作成: ${READ_POLICY_ARN}"
echo ""

# ─── [6/6] IAM の反映待ち ─────────────────────────────────────
echo "[6/6] IAM の変更の反映を待機（10 秒）..."
sleep 10
echo "  リソース情報: ${RESOURCE_FILE}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップが完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "作成したロールは、IAM コンソールの次の画面で確認できます。"
echo "  https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/${ROLE_NAME}"
echo ""
echo "次のステップ: README の手順 1 の「この手順で確かめること」で、作成したロールを IAM コンソールで確認してから、"
echo "            手順 2 に進み、次のコマンドでハンズオン用ロールに切り替えてください。"
echo "  source ./switch-role.sh"

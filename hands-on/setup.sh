#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# IAM access troubleshooter（IAM Toolbox）はプレビュー中、us-east-1 でのみ提供されています。
# authorization ID の照会は「拒否が起きたのと同じリージョン」で行う必要があるため、
# 拒否を起こすためのリソースもすべて us-east-1 に作ります。
readonly PROJECT_NAME="aws-deepcuts"
readonly REGION="us-east-1"
readonly ROLE_NAME="${PROJECT_NAME}-toolbox-subject"
readonly BOUNDARY_NAME="${PROJECT_NAME}-toolbox-boundary"
readonly INLINE_POLICY_NAME="${PROJECT_NAME}-toolbox-subject-policy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Toolbox セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── [1/6] 前提チェック ─────────────────────────────────────────
echo "[1/6] 前提を確認..."
if [[ -f "${RESOURCE_FILE}" ]]; then
  echo "❌ Error: ${RESOURCE_FILE} が既に存在します。前回の環境が残っています。" >&2
  echo "   先に bash ./cleanup.sh を実行してください。" >&2
  exit 1
fi
if ! aws iam-toolbox get-request-authorization-details --generate-cli-skeleton input >/dev/null 2>&1; then
  echo "❌ Error: この AWS CLI は iam-toolbox コマンドに対応していません。" >&2
  echo "   AWS CLI v2 を最新版に更新してください（CloudShell では通常 'sudo yum update -y awscli' は不要で、最新版が入っています）。" >&2
  exit 1
fi
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || {
  echo "❌ Error: AWS 認証情報が取得できません。AWS CLI の設定を確認してください。" >&2
  exit 1
}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  実行者: ${CALLER_ARN}"
echo "  アカウント: ${ACCOUNT_ID}"
echo "  リージョン: ${REGION}（プレビュー提供リージョン）"
echo ""

# ─── [2/6] アクセス許可の境界（顧客管理ポリシー） ────────────────
# 図鑑のケース C 用: ID ベースポリシーでは DynamoDB を許可するが、境界には DynamoDB が無い。
echo "[2/6] アクセス許可の境界ポリシーを作成..."
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${BOUNDARY_NAME}"
if aws iam get-policy --policy-arn "${BOUNDARY_ARN}" >/dev/null 2>&1; then
  echo "  ℹ️  既に存在します: ${BOUNDARY_ARN}"
else
  aws iam create-policy --policy-name "${BOUNDARY_NAME}" \
    --description "AWS Deep Cuts IAM Toolbox hands-on: permissions boundary without DynamoDB" \
    --tags "Key=Project,Value=${PROJECT_NAME}" \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Sid": "BoundaryWithoutDynamoDB",
        "Effect": "Allow",
        "Action": ["s3:*", "sqs:*", "sns:*", "lambda:*", "iam:PassRole", "sts:*"],
        "Resource": "*"
      }]
    }' >/dev/null
  echo "  作成: ${BOUNDARY_ARN}"
fi
echo ""

# ─── [3/6] 「拒否される側」のロール ─────────────────────────────
# 信頼ポリシーは自アカウントの root。実行者（あなた）が sts:AssumeRole できれば引き受けられます。
echo "[3/6] 拒否される側のロールを作成..."
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "  ℹ️  既に存在します: ${ROLE_ARN}"
else
  aws iam create-role --role-name "${ROLE_NAME}" \
    --description "AWS Deep Cuts IAM Toolbox hands-on: the principal that gets denied" \
    --permissions-boundary "${BOUNDARY_ARN}" \
    --tags "Key=Project,Value=${PROJECT_NAME}" \
    --assume-role-policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Principal\": {\"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\"},
        \"Action\": \"sts:AssumeRole\"
      }]
    }" >/dev/null
  echo "  作成: ${ROLE_ARN}"
fi

# S3 バケット名はここで決めておく（インラインポリシーとバケットポリシーの両方で使う）
BUCKET_NAME="${PROJECT_NAME}-toolbox-${ACCOUNT_ID}-$(date +%Y%m%d-%H%M%S)"

# ID ベースポリシー（インライン）。各 Sid が図鑑のどのケースに対応するかはコメント参照。
aws iam put-role-policy --role-name "${ROLE_NAME}" --policy-name "${INLINE_POLICY_NAME}" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"AllowReadHandsOnBucket\",
        \"Effect\": \"Allow\",
        \"Action\": [\"s3:GetObject\", \"s3:ListBucket\"],
        \"Resource\": [\"arn:aws:s3:::${BUCKET_NAME}\", \"arn:aws:s3:::${BUCKET_NAME}/*\"]
      },
      {
        \"Sid\": \"DenyListAllMyBuckets\",
        \"Effect\": \"Deny\",
        \"Action\": \"s3:ListAllMyBuckets\",
        \"Resource\": \"*\"
      },
      {
        \"Sid\": \"AllowDynamoDBListTables\",
        \"Effect\": \"Allow\",
        \"Action\": \"dynamodb:ListTables\",
        \"Resource\": \"*\"
      },
      {
        \"Sid\": \"AllowSNSListTopics\",
        \"Effect\": \"Allow\",
        \"Action\": \"sns:ListTopics\",
        \"Resource\": \"*\"
      },
      {
        \"Sid\": \"AllowCreateFunctionWithoutPassRole\",
        \"Effect\": \"Allow\",
        \"Action\": \"lambda:CreateFunction\",
        \"Resource\": \"*\"
      }
    ]
  }"
echo "  インラインポリシー: ${INLINE_POLICY_NAME}"
echo ""

# ─── [4/6] S3 バケットとバケットポリシー ─────────────────────────
# 図鑑のケース E 用: バケットポリシーで secret/ 配下だけ、このロールに対して明示的に Deny する。
echo "[4/6] S3 バケットを作成..."
aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" >/dev/null   # us-east-1 は LocationConstraint 不要
aws s3api put-public-access-block --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "hello from AWS Deep Cuts" | aws s3 cp - "s3://${BUCKET_NAME}/public/hello.txt" --region "${REGION}" >/dev/null
echo "this is the secret"        | aws s3 cp - "s3://${BUCKET_NAME}/secret/secret.txt" --region "${REGION}" >/dev/null
aws s3api put-bucket-policy --bucket "${BUCKET_NAME}" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"DenySecretPrefixForSubjectRole\",
    \"Effect\": \"Deny\",
    \"Principal\": {\"AWS\": \"${ROLE_ARN}\"},
    \"Action\": \"s3:GetObject\",
    \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/secret/*\"
  }]
}"
echo "  バケット: s3://${BUCKET_NAME}（public/hello.txt, secret/secret.txt）"
echo ""

# ─── [5/6] IAM の伝播待ち ───────────────────────────────────────
echo "[5/6] IAM の変更が伝播するのを待機（10 秒）..."
sleep 10
echo ""

# ─── [6/6] リソース情報を保存 ───────────────────────────────────
echo "[6/6] リソース情報を保存..."
cat > "${RESOURCE_FILE}" <<EOF
# AWS Deep Cuts IAM Toolbox - リソース情報（setup.sh が自動生成）
REGION="${REGION}"
ACCOUNT_ID="${ACCOUNT_ID}"
ROLE_NAME="${ROLE_NAME}"
ROLE_ARN="${ROLE_ARN}"
BOUNDARY_ARN="${BOUNDARY_ARN}"
INLINE_POLICY_NAME="${INLINE_POLICY_NAME}"
BUCKET_NAME="${BUCKET_NAME}"
EOF
echo "  ${RESOURCE_FILE}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップが完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "次のステップ: bash ./denied.sh で「AccessDenied 図鑑」を実行してください。"

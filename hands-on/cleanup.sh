#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Toolbox クリーンアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ! -f "${RESOURCE_FILE}" ]]; then
  echo "❌ Error: ${RESOURCE_FILE} が見つかりません。" >&2
  echo "   setup.sh を実行したディレクトリで実行してください。" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${RESOURCE_FILE}"

echo "[1/4] S3 バケットを削除..."
if [[ -n "${BUCKET_NAME:-}" ]]; then
  aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "${REGION}" >/dev/null 2>&1 || true
  aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null || true
  echo "  完了: ${BUCKET_NAME}"
fi
echo ""

echo "[2/4] ロールを削除..."
# ケース F で万一 Lambda 関数が作られていたら削除する
aws lambda delete-function --function-name "aws-deepcuts-toolbox-dummy" --region "${REGION}" 2>/dev/null || true
if [[ -n "${ROLE_NAME:-}" ]]; then
  aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${INLINE_POLICY_NAME}" 2>/dev/null || true
  aws iam delete-role-permissions-boundary --role-name "${ROLE_NAME}" 2>/dev/null || true
  aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
  echo "  完了: ${ROLE_NAME}"
fi
echo ""

echo "[3/4] 境界ポリシーを削除..."
if [[ -n "${BOUNDARY_ARN:-}" ]]; then
  aws iam delete-policy --policy-arn "${BOUNDARY_ARN}" 2>/dev/null || true
  echo "  完了: ${BOUNDARY_ARN}"
fi
echo ""

echo "[4/4] ローカルの生成物を削除..."
rm -rf "${SCRIPT_DIR}/output"
rm -f "${RESOURCE_FILE}"
echo "  完了"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ すべてのリソースの削除が完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

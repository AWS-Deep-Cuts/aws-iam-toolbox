#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM 脱出ゲーム クリーンアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [[ "${DEEPCUTS_DETECTIVE:-}" == "1" ]]; then
  echo "❌ Error: 探偵のままです。先に source ./admin.sh で自分に戻ってください。" >&2
  exit 1
fi
if [[ ! -f "${RESOURCE_FILE}" ]]; then
  echo "❌ Error: ${RESOURCE_FILE} が見つかりません。setup.sh を実行したディレクトリで実行してください。" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${RESOURCE_FILE}"

# 管理ポリシーを、デフォルト以外のバージョンごと削除する（ゲーム中に作ったバージョンも消す）
delete_managed_policy() {
  local arn="$1"
  for v in $(aws iam list-policy-versions --policy-arn "${arn}" \
              --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
    aws iam delete-policy-version --policy-arn "${arn}" --version-id "${v}" 2>/dev/null || true
  done
  aws iam delete-policy --policy-arn "${arn}" 2>/dev/null || true
}

echo "[1/4] 金庫（IAM ポリシー）を削除..."
if [[ -n "${VAULT_ARN:-}" ]]; then
  delete_managed_policy "${VAULT_ARN}"
  echo "  完了: ${VAULT_ARN}"
fi
echo ""

echo "[2/4] 探偵ロールを削除..."
if [[ -n "${ROLE_NAME:-}" ]]; then
  for p in $(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${p}" 2>/dev/null || true
  done
  for p in $(aws iam list-role-policies --role-name "${ROLE_NAME}" --query 'PolicyNames' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${p}" 2>/dev/null || true
  done
  aws iam delete-role-permissions-boundary --role-name "${ROLE_NAME}" 2>/dev/null || true
  aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
  echo "  完了: ${ROLE_NAME}"
fi
echo ""

echo "[3/4] 管理ポリシー（境界・免許・封印）を削除..."
[[ -n "${BOUNDARY_ARN:-}" ]] && delete_managed_policy "${BOUNDARY_ARN}" && echo "  完了: ${BOUNDARY_ARN}"
[[ -n "${LICENSE_ARN:-}" ]] && delete_managed_policy "${LICENSE_ARN}" && echo "  完了: ${LICENSE_ARN}"
[[ -n "${SEALED_ARN:-}" ]] && delete_managed_policy "${SEALED_ARN}" && echo "  完了: ${SEALED_ARN}"
echo ""

echo "[4/4] ローカルの生成物を削除..."
rm -f "${RESOURCE_FILE}" "${SCRIPT_DIR:?}/evidence.json"
echo "  完了"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ すべてのリソースの削除が完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

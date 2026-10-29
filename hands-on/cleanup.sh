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

# 管理ポリシーを、アタッチ先から外し、デフォルト以外のバージョンごと削除する（ゲーム中に作ったバージョンも消す）
delete_managed_policy() {
  local arn="$1"
  aws iam get-policy --policy-arn "${arn}" >/dev/null 2>&1 || { echo "  （無し: ${arn}）"; return 0; }
  for r in $(aws iam list-entities-for-policy --policy-arn "${arn}" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "${r}" --policy-arn "${arn}" 2>/dev/null || true
  done
  for v in $(aws iam list-policy-versions --policy-arn "${arn}" \
              --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
    aws iam delete-policy-version --policy-arn "${arn}" --version-id "${v}" 2>/dev/null || true
  done
  aws iam delete-policy --policy-arn "${arn}" 2>/dev/null || true
  echo "  完了: ${arn}"
}

echo "[1/4] 探偵ロールを削除..."
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

echo "[2/4] 管理ポリシー（金庫・境界・免許・封印）を削除..."
for arn in "${VAULT_ARN:-}" "${BOUNDARY_ARN:-}" "${LICENSE_ARN:-}" "${SEALED_ARN:-}"; do
  [[ -n "${arn}" ]] && delete_managed_policy "${arn}"
done
echo ""

echo "[3/4] 残っていないか確認..."
LEFT=0
for arn in "${VAULT_ARN:-}" "${BOUNDARY_ARN:-}" "${LICENSE_ARN:-}" "${SEALED_ARN:-}"; do
  [[ -n "${arn}" ]] && aws iam get-policy --policy-arn "${arn}" >/dev/null 2>&1 && { echo "  ⚠️  残っています: ${arn}"; LEFT=1; }
done
if [[ -n "${ROLE_NAME:-}" ]] && aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "  ⚠️  残っています: ${ROLE_NAME}"; LEFT=1
fi
if [[ "${LEFT}" == "1" ]]; then
  echo "❌ Error: 削除できなかったリソースがあります。権限を確認して、もう一度 bash ./cleanup.sh を実行してください。" >&2
  exit 1
fi
echo "  OK"
echo ""

echo "[4/4] ローカルの生成物を削除..."
rm -f "${RESOURCE_FILE}" "${SCRIPT_DIR:?}/evidence.json"
echo "  完了"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ すべてのリソースの削除が完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

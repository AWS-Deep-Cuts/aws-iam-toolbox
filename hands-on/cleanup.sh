#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# AWS Deep Cuts - IAM Access Troubleshooter ハンズオンの後片付け
# setup.sh が作成したロールとポリシーを、ハンズオンの途中で変更した内容も含めて、すべて削除します。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Access Troubleshooter 後片付け"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [[ "${DEEPCUTS_HANDSON_ROLE:-}" == "1" ]]; then
  echo "❌ Error: ハンズオン用ロールに切り替えたままです。先に source ./switch-back.sh を実行してください。" >&2
  exit 1
fi
if [[ -f "${RESOURCE_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${RESOURCE_FILE}"
else
  # resource-ids.env が無いとき（リポジトリを削除して入れ直した場合など）は、setup.sh と同じ決まった名前から組み立てる
  echo "⚠️  ${RESOURCE_FILE} が見つかりません。setup.sh と同じ名前のリソースを探して削除します。"
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_NAME="aws-deepcuts-handson-role"
  CERT_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/aws-deepcuts-certificate"
  MANAGED_DENY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/aws-deepcuts-managed-deny"
  READ_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/aws-deepcuts-read-certificate"
  BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/aws-deepcuts-boundary"
  echo ""
fi

# 管理ポリシーを、アタッチ先から外し、既定以外のバージョン（ハンズオンで編集したときに作られる）も含めて削除する
delete_managed_policy() {
  local arn="$1"
  aws iam get-policy --policy-arn "${arn}" >/dev/null 2>&1 || { echo "  対象なし: ${arn}"; return 0; }
  for r in $(aws iam list-entities-for-policy --policy-arn "${arn}" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "${r}" --policy-arn "${arn}" 2>/dev/null || true
  done
  for v in $(aws iam list-policy-versions --policy-arn "${arn}" \
              --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
    aws iam delete-policy-version --policy-arn "${arn}" --version-id "${v}" 2>/dev/null || true
  done
  aws iam delete-policy --policy-arn "${arn}" 2>/dev/null || true
  echo "  削除: ${arn}"
}

echo "[1/3] ハンズオン用ロールを削除..."
if [[ -n "${ROLE_NAME:-}" ]] && aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  for p in $(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${p}" 2>/dev/null || true
  done
  for p in $(aws iam list-role-policies --role-name "${ROLE_NAME}" --query 'PolicyNames' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${p}" 2>/dev/null || true
  done
  aws iam delete-role-permissions-boundary --role-name "${ROLE_NAME}" 2>/dev/null || true
  aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
  echo "  削除: ${ROLE_NAME}"
else
  echo "  対象なし"
fi
echo ""

echo "[2/3] 管理ポリシーを削除..."
for arn in "${CERT_ARN:-}" "${MANAGED_DENY_ARN:-}" "${READ_POLICY_ARN:-}" "${BOUNDARY_ARN:-}"; do
  [[ -n "${arn}" ]] && delete_managed_policy "${arn}"
done
echo ""

echo "[3/3] 残っていないか確認..."
LEFT=0
for arn in "${CERT_ARN:-}" "${MANAGED_DENY_ARN:-}" "${READ_POLICY_ARN:-}" "${BOUNDARY_ARN:-}"; do
  if [[ -n "${arn}" ]] && aws iam get-policy --policy-arn "${arn}" >/dev/null 2>&1; then
    echo "  ⚠️  残っています: ${arn}"; LEFT=1
  fi
done
if [[ -n "${ROLE_NAME:-}" ]] && aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "  ⚠️  残っています: ${ROLE_NAME}"; LEFT=1
fi
if [[ "${LEFT}" == "1" ]]; then
  echo "❌ Error: 削除できなかったリソースがあります。権限を確認して、もう一度 bash ./cleanup.sh を実行してください。" >&2
  exit 1
fi
echo "  なし"
rm -f "${RESOURCE_FILE}" "${SCRIPT_DIR:?}/authorization-details.json"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ すべてのリソースの削除が完了しました！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

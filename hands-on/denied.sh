#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

# 「AccessDenied 図鑑」: 原因の違う拒否を意図的に起こし、authorization ID から評価の過程を取得する。
# 使い方: bash ./denied.sh          … 全ケース
#         bash ./denied.sh C        … ケース C だけ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RESOURCE_FILE="${SCRIPT_DIR}/resource-ids.env"
readonly OUT="${SCRIPT_DIR}/output"
readonly CASE_FILTER="${1:-all}"
[[ -f "${RESOURCE_FILE}" ]] || { echo "❌ Error: ${RESOURCE_FILE} が見つかりません。先に bash ./setup.sh を実行してください。" >&2; exit 1; }
# shellcheck source=/dev/null
source "${RESOURCE_FILE}"
mkdir -p "${OUT}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AWS Deep Cuts - IAM Toolbox: AccessDenied 図鑑"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 拒否される側のロールを引き受け、一時認証情報を「AK SK ST」の 1 行で返す
assume_subject() {
  local session="$1" policy="${2:-}"
  local args=(--role-arn "${ROLE_ARN}" --role-session-name "${session}" --duration-seconds 900 --region "${REGION}")
  [[ -n "${policy}" ]] && args+=(--policy "${policy}")
  aws sts assume-role "${args[@]}" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text
}

# エラーメッセージから authorization ID を抜き出す（見つからなければ空）
extract_authorization_id() {
  python3 - <<'EOF'
import re, sys
text = sys.stdin.read()
patterns = [
    r"authorizationId=([0-9a-z]+)",
    r"authorization[-_ ]?details/([0-9a-z]+)",
    r"[Aa]uthorization\s*ID\s*[:=]?\s*[\"']?([0-9a-z]{6,})",
    r"authorization[-_ ]?[iI][dD]\s*[:=]\s*[\"']?([0-9a-z]{6,})",
]
for p in patterns:
    m = re.search(p, text)
    if m:
        print(m.group(1))
        break
EOF
}

# authorization ID から評価の過程を取得する（反映に少し時間がかかることがあるので再試行する）
lookup_details() {
  local case="$1" auth_id="$2"
  for attempt in $(seq 1 8); do
    if aws iam-toolbox get-request-authorization-details --authorization-id "${auth_id}" \
         --region "${REGION}" --output json > "${OUT}/${case}.json" 2> "${OUT}/${case}.lookup.err"; then
      return 0
    fi
    if grep -q ResourceNotFound "${OUT}/${case}.lookup.err"; then
      printf '  （まだ見つかりません。5 秒待って再試行 %d/8）\n' "${attempt}"
      sleep 5
    else
      cat "${OUT}/${case}.lookup.err" >&2
      return 1
    fi
  done
  return 1
}

# 1 ケース実行: run_case <ID> <タイトル> <セッションポリシー JSON または ""> <コマンド...>
run_case() {
  local case="$1" title="$2" policy="$3"
  shift 3
  if [[ "${CASE_FILTER}" != "all" && "${CASE_FILTER}" != "${case}" ]]; then
    return 0
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ケース ${case}: ${title}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  実行: $*"
  [[ -n "${policy}" ]] && echo "  セッションポリシー: ${policy}"
  local ak sk st
  read -r ak sk st < <(assume_subject "deepcuts-case-${case}" "${policy}")
  local err=""
  if err=$(AWS_ACCESS_KEY_ID="${ak}" AWS_SECRET_ACCESS_KEY="${sk}" AWS_SESSION_TOKEN="${st}" "$@" 2>&1 >/dev/null); then
    echo "  ⚠️  拒否されませんでした（期待と異なります）。IAM の伝播待ちの可能性があるので、少し待って再実行してください。"
    echo ""
    return 0
  fi
  printf '%s\n' "${err}" > "${OUT}/${case}.err"
  echo "  エラーメッセージ:"
  printf '%s\n' "${err}" | fold -s -w 100 | sed 's/^/    /'
  local auth_id
  auth_id=$(extract_authorization_id <<< "${err}")
  if [[ -z "${auth_id}" ]]; then
    echo "  ⚠️  authorization ID が含まれていません（対応外のサービス／API、または ID が付与されなかったケース）"
    echo ""
    return 0
  fi
  echo "  authorization ID: ${auth_id}"
  if ! lookup_details "${case}" "${auth_id}"; then
    echo "  ⚠️  評価の詳細を取得できませんでした（output/${case}.lookup.err を確認してください）"
    echo ""
    return 0
  fi
  echo "  → output/${case}.json に保存。読み解き:"
  echo ""
  python3 "${SCRIPT_DIR}/explain.py" "${OUT}/${case}.json" | sed 's/^/  /'
  echo ""
}

# ─── 事前確認: 拒否される側のロールを引き受けられること ──────────
echo "[準備] 拒否される側のロールを引き受けて、自分が誰かを確認..."
read -r AK SK ST < <(assume_subject "deepcuts-whoami")
AWS_ACCESS_KEY_ID="${AK}" AWS_SECRET_ACCESS_KEY="${SK}" AWS_SESSION_TOKEN="${ST}" \
  aws sts get-caller-identity --query Arn --output text | sed 's/^/  /'
echo "  （sts:GetCallerIdentity はポリシーに関係なく常に許可されるので、ここは拒否されません）"
echo ""
echo "[準備] 対照実験: 許可されている操作（public/hello.txt の取得）..."
AWS_ACCESS_KEY_ID="${AK}" AWS_SECRET_ACCESS_KEY="${SK}" AWS_SESSION_TOKEN="${ST}" \
  aws s3api get-object --bucket "${BUCKET_NAME}" --key public/hello.txt --region "${REGION}" "${OUT}/hello.txt" >/dev/null \
  && echo "  取得できました: $(cat "${OUT}/hello.txt")"
echo ""

# ─── 図鑑 ──────────────────────────────────────────────────────
run_case A "暗黙の拒否 — どのポリシーにも Allow が無い" "" \
  aws sqs list-queues --region "${REGION}"

run_case B "ID ベースポリシーの明示的 Deny（Sid: DenyListAllMyBuckets）" "" \
  aws s3api list-buckets --region "${REGION}"

run_case C "アクセス許可の境界 — ID ベースポリシーは Allow なのに、境界に DynamoDB が無い" "" \
  aws dynamodb list-tables --region "${REGION}"

run_case D "セッションポリシー — assume-role 時に渡したポリシーの Deny" \
  '{"Version":"2012-10-17","Statement":[{"Sid":"DenyInSession","Effect":"Deny","Action":"sns:ListTopics","Resource":"*"}]}' \
  aws sns list-topics --region "${REGION}"

run_case E "リソースベースポリシー — S3 バケットポリシーの明示的 Deny（secret/ 配下）" "" \
  aws s3api get-object --bucket "${BUCKET_NAME}" --key secret/secret.txt --region "${REGION}" "${OUT}/secret.txt"

# ケース F 用のダミー ZIP（中身は使われない。iam:PassRole で止まる想定）
python3 - "${OUT}/dummy.zip" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("index.py", "def handler(event, context):\n    return 'never deployed'\n")
EOF
run_case F "1 リクエストで複数の評価 — lambda:CreateFunction は Allow、iam:PassRole が無い" "" \
  aws lambda create-function --function-name "aws-deepcuts-toolbox-dummy" --runtime python3.13 \
    --role "${ROLE_ARN}" --handler index.handler --zip-file "fileb://${OUT}/dummy.zip" --region "${REGION}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 図鑑の実行が完了しました！（結果: ${OUT}/）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

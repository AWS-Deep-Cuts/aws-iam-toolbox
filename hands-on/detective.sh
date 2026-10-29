#!/bin/bash
# 探偵ロールに変身する。必ず source で実行する:  source ./detective.sh [--disguise]
#   --disguise … セッションポリシー付きで変身する（裏ボス用）
# ※ source されるスクリプトなので set -e は使わない（あなたのシェルが落ちるため）

_DEEPCUTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${_DEEPCUTS_DIR}/resource-ids.env" ]]; then
  echo "❌ resource-ids.env が見つかりません。先に bash ./setup.sh を実行してください。"
  return 1 2>/dev/null || exit 1
fi
# shellcheck source=/dev/null
source "${_DEEPCUTS_DIR}/resource-ids.env"

# いったん自分（管理者）に戻ってから変身する（探偵のまま assume-role はできない）
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
_DEEPCUTS_ARGS=(--role-arn "${ROLE_ARN}" --role-session-name "detective-$(date +%H%M%S)" --duration-seconds 3600 --region "${REGION}")
if [[ "${1:-}" == "--disguise" ]]; then
  _DEEPCUTS_ARGS+=(--policy '{"Version":"2012-10-17","Statement":[{"Sid":"Disguise","Effect":"Deny","Action":"iam:GetPolicy","Resource":"*"}]}')
fi
if ! _DEEPCUTS_CREDS=$(aws sts assume-role "${_DEEPCUTS_ARGS[@]}" \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text); then
  echo "❌ 探偵ロールを引き受けられませんでした。setup.sh 直後なら 10〜20 秒待って再実行してください。"
  return 1 2>/dev/null || exit 1
fi
read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "${_DEEPCUTS_CREDS}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export DEEPCUTS_DETECTIVE=1
if [[ -z "${DEEPCUTS_OLD_PS1:-}" ]]; then export DEEPCUTS_OLD_PS1="${PS1:-}"; fi
export PS1="🕵️  探偵 $ "
unset _DEEPCUTS_CREDS _DEEPCUTS_ARGS
echo "🕵️  探偵になりました: $(aws sts get-caller-identity --query Arn --output text)"
if [[ "${1:-}" == "--disguise" ]]; then echo "   （変装中: セッションポリシー付き）"; fi
echo "   金庫を開ける: aws iam get-policy --policy-arn ${VAULT_ARN} --query Policy.Description --output text"
echo "   自分に戻る:   source ./admin.sh"

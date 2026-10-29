#!/bin/bash
# 探偵ロールに変身する。必ず source で実行する:  source ./detective.sh [--disguise]
#   --disguise … セッションポリシー付きで変身する（裏ボス用）
# ※ source されるスクリプトなので set -e は使わない（あなたのシェルが落ちるため）
# ※ CloudShell 用。手元の端末で AWS_ACCESS_KEY_ID などの環境変数で認証している場合は実行しないでください（消えます）

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "❌ このスクリプトは source で実行してください:  source ./detective.sh" >&2
  exit 1
fi
if [[ -z "${DEEPCUTS_DETECTIVE:-}" && -n "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_CONTAINER_CREDENTIALS_FULL_URI:-}" ]]; then
  echo "❌ 環境変数 AWS_ACCESS_KEY_ID で認証しているようです。このスクリプトは探偵⇄管理者の切り替えに環境変数を使うため、"
  echo "   管理者の認証情報が消えてしまいます。CloudShell で実行するか、プロファイル（~/.aws/credentials や SSO）で認証してください。"
  return 1
fi

_DEEPCUTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${_DEEPCUTS_DIR}/resource-ids.env" ]]; then
  echo "❌ resource-ids.env が見つかりません。先に bash ./setup.sh を実行してください。"
  return 1
fi
# shellcheck source=/dev/null
source "${_DEEPCUTS_DIR}/resource-ids.env"

# いったん自分（管理者）に戻ってから変身する（探偵のまま assume-role はできない）
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN DEEPCUTS_DETECTIVE
if [[ -n "${DEEPCUTS_OLD_PS1:-}" ]]; then PS1="${DEEPCUTS_OLD_PS1}"; unset DEEPCUTS_OLD_PS1; fi
_DEEPCUTS_ARGS=(--role-arn "${ROLE_ARN}" --role-session-name "detective-$(date +%H%M%S)" --duration-seconds 3600 --region "${REGION}")
if [[ "${1:-}" == "--disguise" ]]; then
  _DEEPCUTS_ARGS+=(--policy '{"Version":"2012-10-17","Statement":[{"Sid":"Disguise","Effect":"Deny","Action":"iam:GetPolicy","Resource":"*"}]}')
fi
if ! _DEEPCUTS_CREDS=$(aws sts assume-role "${_DEEPCUTS_ARGS[@]}" \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text); then
  echo "❌ 探偵ロールを引き受けられませんでした（今は管理者のままです）。setup.sh 直後なら 10〜20 秒待って再実行してください。"
  echo "   ルートユーザーは sts:AssumeRole を呼べません。IAM ユーザーまたは Identity Center のユーザーで実行してください。"
  unset _DEEPCUTS_ARGS
  return 1
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

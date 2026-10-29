#!/bin/bash
# ハンズオン用ロール（aws-deepcuts-handson-role）に切り替える。必ず source で実行する。
#   source ./switch-role.sh                    … ロールに切り替える
#   source ./switch-role.sh --session-policy   … セッションポリシーを付けて切り替える（追加ステージ）
# 管理者に戻るときは: source ./switch-back.sh
#
# このスクリプトは、sts:AssumeRole で発行された一時的な認証情報を、環境変数（AWS_ACCESS_KEY_ID など）に設定する。
# CloudShell 用。手元の端末で、環境変数に設定した認証情報を使っている場合は実行しない（環境変数が上書きされる）。
# source で実行されるため、set -e は使わない（失敗したときに、あなたのシェルごと終了してしまうため）。

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "❌ このスクリプトは source で実行してください:  source ./switch-role.sh" >&2
  exit 1
fi
if [[ -z "${DEEPCUTS_HANDSON_ROLE:-}" && -n "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_CONTAINER_CREDENTIALS_FULL_URI:-}" ]]; then
  echo "❌ 環境変数 AWS_ACCESS_KEY_ID の認証情報を使っているようです。このスクリプトは環境変数を上書きするため、"
  echo "   管理者の認証情報が失われます。CloudShell で実行するか、プロファイル（~/.aws/credentials や SSO）を使ってください。"
  return 1
fi

_DEEPCUTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${_DEEPCUTS_DIR}/resource-ids.env" ]]; then
  echo "❌ resource-ids.env が見つかりません。先に bash ./setup.sh を実行してください。"
  return 1
fi
# shellcheck source=/dev/null
source "${_DEEPCUTS_DIR}/resource-ids.env"

# いったん管理者に戻ってから切り替える（ハンズオン用ロールには、ロールに切り替える権限が無いため）
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN DEEPCUTS_HANDSON_ROLE
if [[ -n "${DEEPCUTS_OLD_PS1:-}" ]]; then PS1="${DEEPCUTS_OLD_PS1}"; unset DEEPCUTS_OLD_PS1; fi

_DEEPCUTS_ARGS=(--role-arn "${ROLE_ARN}" --role-session-name "handson-$(date +%H%M%S)" --duration-seconds 3600 --region "${REGION}")
if [[ "${1:-}" == "--session-policy" ]]; then
  # 追加ステージ: セッションポリシーで iam:GetPolicy を Deny する。ロールのポリシーには書かれていない Deny になる
  _DEEPCUTS_ARGS+=(--policy '{"Version":"2012-10-17","Statement":[{"Sid":"DenyReadCertificateInSession","Effect":"Deny","Action":"iam:GetPolicy","Resource":"*"}]}')
fi
if ! _DEEPCUTS_CREDS=$(aws sts assume-role "${_DEEPCUTS_ARGS[@]}" \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text); then
  echo "❌ ハンズオン用ロールに切り替えられませんでした。管理者のままです。"
  echo "   setup.sh の直後であれば、10〜20 秒待ってから、もう一度実行してください。"
  unset _DEEPCUTS_ARGS
  return 1
fi
read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "${_DEEPCUTS_CREDS}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export DEEPCUTS_HANDSON_ROLE=1
export DEEPCUTS_OLD_PS1="${PS1:-}"
export PS1="(handson-role) \$ "
unset _DEEPCUTS_CREDS _DEEPCUTS_ARGS
echo "ハンズオン用ロールに切り替えました: $(aws sts get-caller-identity --query Arn --output text)"
if [[ "${1:-}" == "--session-policy" ]]; then echo "  セッションポリシーを付けています。"; fi
echo "  修了証のポリシーを読み取る: aws iam get-policy --policy-arn \"\${CERT_ARN}\" --query Policy.Description --output text"
echo "  管理者に戻る:             source ./switch-back.sh"

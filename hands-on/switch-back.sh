#!/bin/bash
# ハンズオン用ロールから、管理者（あなた自身の認証情報）に戻る。必ず source で実行する:  source ./switch-back.sh
# CloudShell 用。手元の端末で、環境変数に設定した認証情報を使っている場合は実行しない（環境変数が消える）。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "❌ このスクリプトは source で実行してください:  source ./switch-back.sh" >&2
  exit 1
fi
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN DEEPCUTS_HANDSON_ROLE
if [[ -n "${DEEPCUTS_OLD_PS1:-}" ]]; then export PS1="${DEEPCUTS_OLD_PS1}"; unset DEEPCUTS_OLD_PS1; fi
echo "管理者に戻りました: $(aws sts get-caller-identity --query Arn --output text)"

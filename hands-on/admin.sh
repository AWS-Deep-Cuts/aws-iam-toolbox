#!/bin/bash
# 探偵から自分（管理者）に戻る。必ず source で実行する:  source ./admin.sh
# ※ CloudShell 用。手元の端末で AWS_ACCESS_KEY_ID などの環境変数で認証している場合は実行しないでください（消えます）
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "❌ このスクリプトは source で実行してください:  source ./admin.sh" >&2
  exit 1
fi
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN DEEPCUTS_DETECTIVE
if [[ -n "${DEEPCUTS_OLD_PS1:-}" ]]; then export PS1="${DEEPCUTS_OLD_PS1}"; unset DEEPCUTS_OLD_PS1; fi
echo "🧑‍💼 自分に戻りました: $(aws sts get-caller-identity --query Arn --output text)"

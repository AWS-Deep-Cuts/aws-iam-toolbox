#!/usr/bin/env python3
"""AWS Deep Cuts - IAM Access Troubleshooter: get-request-authorization-details の応答（評価の詳細）を読みやすく整形する

使い方:
  aws iam-toolbox get-request-authorization-details --authorization-id <ID> --region us-east-1 --output json > authorization-details.json
  python3 explain.py authorization-details.json          # または `... | python3 explain.py -`

最後の「→ 原因の候補」は、このスクリプトが評価の詳細から推測したものです。AWS の応答には含まれません。
Python の標準ライブラリだけで動きます。
"""
import json
import sys

EFFECT_LABEL = {
    "ALLOW": "許可",
    "EXPLICIT_DENY": "明示的な拒否（Deny のステートメントに一致した）",
    "IMPLICIT_DENY": "暗黙的な拒否（必要な Allow が無い）",
}
POLICY_LABEL = {
    "IDENTITY_BASED_POLICY": "ID ベースポリシー",
    "RESOURCE_BASED_POLICY": "リソースベースポリシー",
    "PERMISSIONS_BOUNDARY": "アクセス許可の境界",
    "SESSION_POLICY": "セッションポリシー",
    "SERVICE_CONTROL_POLICY": "SCP（サービスコントロールポリシー）",
    "RESOURCE_CONTROL_POLICY": "RCP（リソースコントロールポリシー）",
    "VPC_ENDPOINT_POLICY": "VPC エンドポイントポリシー",
}
# IAM のポリシーの評価で、各ポリシーの種類が「許可を与えるポリシー」か「許可を絞るポリシー」か
GRANT_TYPES = {"IDENTITY_BASED_POLICY", "RESOURCE_BASED_POLICY"}
GATE_TYPES = {"PERMISSIONS_BOUNDARY", "SESSION_POLICY", "SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "VPC_ENDPOINT_POLICY"}


def load(path):
    try:
        with (open(path, encoding="utf-8") if path != "-" else sys.stdin) as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        sys.exit(f"❌ {path} を JSON として読めませんでした（{e}）。\n"
                 "   get-request-authorization-details が ResourceNotFoundException などで失敗していないか確認し、"
                 "数秒待ってからもう一度実行してください。")


def short(value, width=100):
    text = json.dumps(value, ensure_ascii=False) if not isinstance(value, str) else value
    return text if len(text) <= width else text[: width - 1] + "…"


def kind(pol):
    if pol.get("inline") is True:
        return "（インライン）"
    if pol.get("inline") is False:
        return "（管理ポリシー）"
    return ""


def explain(doc):
    policies = {p.get("uri"): p for p in doc.get("policies", [])}
    request_context = doc.get("requestContext", {}) or {}

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  リクエストのコンテキスト（リクエスト全体に共通する条件キーと値）")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for key, value in sorted(request_context.items()):
        print(f"  {key} = {short(value)}")
    print()

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  評価（アクションとリソースの組ごとの判定）")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for i, ev in enumerate(doc.get("evaluations", []), 1):
        effect = ev.get("evaluatedEffect", "?")
        print(f"[{i}] {ev.get('action')}  on  {ev.get('resource') or '(リソース指定なし)'}")
        print(f"    判定: {effect} — {EFFECT_LABEL.get(effect, '')}")
        for key, value in sorted((ev.get("context") or {}).items()):
            print(f"    context: {key} = {short(value)}")
        matched = ev.get("matchedPolicies") or []
        if not matched:
            print("    一致したポリシー: なし")
        for mp in matched:
            pol = policies.get(mp.get("uri"), {})
            ptype = pol.get("type", "?")
            attached = ", ".join(a.get("arn", "?") for a in pol.get("attachedTo", []) or [])
            print(f"    一致: {POLICY_LABEL.get(ptype, ptype)}{kind(pol)}  {mp.get('uri')}")
            if attached:
                print(f"          アタッチ先: {attached}")
            for st in mp.get("matchedStatements") or []:
                print(f"          ステートメント Sid={st.get('sid')!r} → {st.get('evaluatedEffect')}")
        print(f"    → 原因の候補（スクリプトによる推測）: {verdict(ev, policies, request_context)}")
        print()

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  評価されたポリシーの一覧")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for pol in doc.get("policies", []):
        ptype = pol.get("type", "?")
        attached = ", ".join(a.get("arn", "?") for a in pol.get("attachedTo", []) or [])
        print(f"  - {POLICY_LABEL.get(ptype, ptype)}{kind(pol)}")
        print(f"      uri: {pol.get('uri')}")
        if attached:
            print(f"      アタッチ先: {attached}")
    if not doc.get("policies"):
        print("  （なし）")
    if doc.get("nextToken"):
        print("\n  （評価がまだ続きます。--next-token で次のページを取得してください）")


def verdict(ev, policies, request_context):
    """評価 1 件から、拒否の原因の読み方を文章にする（IAM のポリシーの評価の順序に沿う）。"""
    effect = ev.get("evaluatedEffect")
    matched = ev.get("matchedPolicies") or []
    if effect == "ALLOW":
        return "許可されています。"
    if effect == "EXPLICIT_DENY":
        culprits = []
        for mp in matched:
            ptype = policies.get(mp.get("uri"), {}).get("type", "?")
            for st in mp.get("matchedStatements") or []:
                if st.get("evaluatedEffect") == "DENY":
                    culprits.append(f"{POLICY_LABEL.get(ptype, ptype)} の Sid={st.get('sid')!r}")
        return "Deny のステートメントに一致したため拒否されました。原因: " + ("、".join(culprits) if culprits else "一致した DENY のステートメントの情報がありません")

    # IMPLICIT_DENY: API リファレンスによると、一致したポリシーは返らない。評価されたポリシーの種類から候補を絞る。
    # ただし、AWS Organizations の組織に属するアカウントでは、SCP の Allow が一致したポリシーに並ぶことがある
    allow_types = {policies.get(mp.get("uri"), {}).get("type") for mp in matched
                   if any(st.get("evaluatedEffect") == "ALLOW" for st in (mp.get("matchedStatements") or []))}
    evaluated_types = {p.get("type") for p in policies.values()}
    gates_present = sorted(t for t in evaluated_types if t in GATE_TYPES)
    context_keys = set(request_context) | set(ev.get("context") or {})
    tag_keys = sorted(k for k in context_keys if k.startswith("aws:PrincipalTag/") or k.startswith("aws:RequestTag/") or k.startswith("aws:ResourceTag/"))

    if allow_types & GRANT_TYPES:
        gates = [g for g in gates_present if g not in allow_types]
        if gates:
            return ("ID ベースポリシーかリソースベースポリシーは Allow していますが、拒否されています。原因の候補は、Allow が無い "
                    + "、".join(POLICY_LABEL[g] for g in gates) + " です。")
        return "ID ベースポリシーは Allow していますが、拒否されています。許可を絞るポリシー（SCP・RCP・アクセス許可の境界・セッションポリシー）が許可していない可能性があります。"

    if not (evaluated_types & GRANT_TYPES):
        msg = ("評価されたポリシーに ID ベースポリシーが 1 つもありません。このユーザーやロールには、このアクションを許可するポリシーがありません。"
               "このアクションを Allow する ID ベースポリシーを追加してください。")
    else:
        # 暗黙的な拒否では一致したポリシーが返らないため、ID ベースポリシーの Allow が一致したかどうかは、この応答からは分からない
        msg = ("暗黙的な拒否のため、一致したポリシーは表示されません。評価されたポリシーには、ID ベースポリシーがあります。"
               "原因は次のどちらかです。(1) ID ベースポリシーの Allow の Condition を、コンテキストの値が満たしていない。")
        if tag_keys:
            msg += "条件キーの値: " + ", ".join(f"{k} = {short(request_context.get(k, (ev.get('context') or {}).get(k)), 40)}" for k in tag_keys) + "。"
        if gates_present:
            msg += ("(2) 評価されたポリシーにある" + "、".join(POLICY_LABEL[g] for g in gates_present)
                    + "が、同じアクションを Allow していない。")
        else:
            msg += "(2) Allow のステートメントの Action か Resource が、リクエストに当てはまっていない。"
        msg += ("エラーメッセージの拒否の理由が `no identity-based policy allows` であれば ID ベースポリシーの Condition と書き方を、"
                "`no permissions boundary allows` であればアクセス許可の境界を確かめてください。")
    if "SERVICE_CONTROL_POLICY" in allow_types:
        msg += " SCP の ALLOW の一致は「SCP は拒否していない」という意味で、拒否の原因ではありません。"
    return msg


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    explain(load(sys.argv[1]))

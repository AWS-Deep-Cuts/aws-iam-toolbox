#!/usr/bin/env python3
"""AWS Deep Cuts - IAM Toolbox: get-request-authorization-details の応答を読みやすく整形する

使い方:
  aws iam-toolbox get-request-authorization-details --authorization-id <ID> --region us-east-1 > output/case-A.json
  python3 explain.py output/case-A.json

標準ライブラリのみ（CloudShell でそのまま動く）。
"""
import json
import sys

EFFECT_LABEL = {
    "ALLOW": "許可",
    "EXPLICIT_DENY": "明示的な拒否",
    "IMPLICIT_DENY": "暗黙的な拒否（どのポリシーも許可していない）",
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
# IAM のポリシー評価ロジックで、各ポリシータイプが「許可を与える側」か「許可を絞る側」か
GATE_TYPES = {"PERMISSIONS_BOUNDARY", "SESSION_POLICY", "SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "VPC_ENDPOINT_POLICY"}


def load(path):
    with (open(path, encoding="utf-8") if path != "-" else sys.stdin) as fh:
        return json.load(fh)


def short(value, width=100):
    text = json.dumps(value, ensure_ascii=False) if not isinstance(value, str) else value
    return text if len(text) <= width else text[: width - 1] + "…"


def explain(doc):
    policies = {p.get("uri"): p for p in doc.get("policies", [])}

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  リクエストコンテキスト（リクエスト全体に共通する条件キー）")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for key, value in sorted(doc.get("requestContext", {}).items()):
        print(f"  {key} = {short(value)}")
    print()

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  評価（アクション × リソースごとの判定）")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for i, ev in enumerate(doc.get("evaluations", []), 1):
        effect = ev.get("evaluatedEffect", "?")
        print(f"[{i}] {ev.get('action')}  on  {ev.get('resource') or '(リソース指定なし)'}")
        print(f"    判定: {effect} — {EFFECT_LABEL.get(effect, '')}")
        for key, value in sorted((ev.get("context") or {}).items()):
            print(f"    context: {key} = {short(value)}")
        matched = ev.get("matchedPolicies") or []
        if not matched:
            print("    マッチしたポリシー: なし")
        for mp in matched:
            pol = policies.get(mp.get("uri"), {})
            ptype = pol.get("type", "?")
            attached = ", ".join(a.get("arn", "?") for a in pol.get("attachedTo", []) or [])
            print(f"    マッチ: {POLICY_LABEL.get(ptype, ptype)}{'（インライン）' if pol.get('inline') else ''}  {mp.get('uri')}")
            if attached:
                print(f"          アタッチ先: {attached}")
            for st in mp.get("matchedStatements") or []:
                print(f"          ステートメント Sid={st.get('sid')!r} → {st.get('evaluatedEffect')}")
        print(f"    → 読み方: {verdict(ev, policies)}")
        print()

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  評価対象になったポリシー一覧")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for pol in doc.get("policies", []):
        ptype = pol.get("type", "?")
        attached = ", ".join(a.get("arn", "?") for a in pol.get("attachedTo", []) or [])
        print(f"  - {POLICY_LABEL.get(ptype, ptype)}{'（インライン）' if pol.get('inline') else '（管理ポリシー）' if pol.get('inline') is False else ''}")
        print(f"      uri: {pol.get('uri')}")
        if attached:
            print(f"      アタッチ先: {attached}")
    if doc.get("nextToken"):
        print("\n  （評価がまだ続きます。--next-token で次のページを取得してください）")


def verdict(ev, policies):
    """評価 1 件から「真犯人」を文章にする（IAM のポリシー評価ロジックに沿った読み方）。"""
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
        return "明示的な Deny が勝っています。真犯人: " + ("、".join(culprits) if culprits else "（DENY ステートメントの情報なし）")
    # IMPLICIT_DENY
    allow_types = {policies.get(mp.get("uri"), {}).get("type") for mp in matched
                   if any(st.get("evaluatedEffect") == "ALLOW" for st in (mp.get("matchedStatements") or []))}
    evaluated_types = {p.get("type") for p in policies.values()}
    if not matched:
        gates = sorted(t for t in evaluated_types if t in GATE_TYPES)
        if gates:
            return ("どのポリシーにも Allow がありません。評価されたポリシーには "
                    + "、".join(POLICY_LABEL[g] for g in gates)
                    + " も含まれており、ID ベースポリシーの Allow だけでは足りない状況です。")
        return "どの ID ベースポリシーにも、このアクション・リソースを許可するステートメントがありません。"
    if "IDENTITY_BASED_POLICY" in allow_types:
        gates = sorted(t for t in evaluated_types if t in GATE_TYPES and t not in allow_types)
        if gates:
            return ("ID ベースポリシーは Allow しているのに拒否されています。真犯人は "
                    + "、".join(POLICY_LABEL[g] for g in gates)
                    + "（その層に Allow が無い）です。")
        return "ID ベースポリシーは Allow しているのに拒否されています。別の層（SCP / RCP / 境界 / セッションポリシー）が許可していない可能性があります。"
    return "Allow はあるものの、必要な層すべてで許可されていません。マッチしたポリシーのタイプを確認してください。"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    explain(load(sys.argv[1]))

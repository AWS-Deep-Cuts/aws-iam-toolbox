このリポジトリは AWS Deep Cuts の、IAM Toolbox（IAM Access Troubleshooter）に関するハンズオンコンテンツです。

<!-- TODO: 記事公開後にリンクを追加 -->
<!-- IAM Access Troubleshooter の解説記事(Qiita)は[こちら]() -->

解説記事の原稿は [article/aws-iam-toolbox.md](./article/aws-iam-toolbox.md) にあります。

> **Note**: このハンズオンは、2026 年 8 月からプレビュー提供中の **IAM Access Troubleshooter** を使います（2026 年 10 月時点の情報です。プレビュー機能のため、画面や仕様は今後変わる可能性があります）。
> - 提供リージョンは **バージニア北部（us-east-1）のみ** です。**東京リージョン（ap-northeast-1）ではまだ使えません**（対応リージョンは順次拡大中とされています）。「拒否が起きたのと同じリージョンで照会する」必要があるため、ハンズオンはすべて us-east-1 の CloudShell で行います
> - authorization ID が付くのは **主に IAM の API** で、他のサービスには順次広がっている段階です。そのため、このゲームの「金庫」も IAM のリソース（管理ポリシー）にしています
> - AWS CLI は `aws iam-toolbox` に対応した **v2.36.31 以降**（2026 年 8 月 25 日リリース）が必要です。CloudShell の AWS CLI は最新版とは限らないので、`aws --version` で確認し、古ければ [前提条件](#前提条件) の手順でホームディレクトリに最新版を入れてください（setup.sh も冒頭で検査します）
>
> 名前が 3 つ出てきますが、同じものです。コンソールでは **Access Troubleshooter**、API / CLI では **IAM Toolbox**（`aws iam-toolbox get-request-authorization-details`）、必要な権限は `iam:GetRequestAuthorizationDetails`。この README では Access Troubleshooter と呼びます。

> 💰 **コストについて**
>
> 作成するのは IAM ロールと IAM ポリシーだけで、料金は 0 円です（IAM は無料で、Access Troubleshooter にも 2026 年 10 月時点で料金表はありません）。それでも、遊び終わったら後片付けをしてください。

# AWS Deep Cutsとは
AWS Deep Cutsは、AWS の最新のサービスやニッチな機能、または高度にアカデミックな知識を要求するサービスなど、多くの人が知らない 『隠れた名曲 = **Deep Cuts**』 を深くまで掘り下げる技術シリーズです。

このようなサービスはWeb情報も少なく、初学者は気軽にキャッチアップできないのが実情です。

そこで AWS Deep Cuts シリーズでは、**前提知識も含めた分かりやすいサービス解説** と **手順通りに進めれば誰でも再現できるハンズオン** を提供します！

# このハンズオンの物語 — IAM 脱出ゲーム

`AccessDenied`。AWS を使っていて、これほど見たくないのに頻繁に見る単語はありません。しかも犯人が分かりません。ID ベースポリシーに Allow が無いのか、どこかに Deny があるのか、アクセス許可の境界か、バケットポリシーか、SCP か。これまでは「ポリシーを全部読んで推理する」しかありませんでした。

2026 年 8 月、IAM は AccessDenied のエラーメッセージに **authorization ID** を付けるようになりました。この ID を **IAM Access Troubleshooter** に渡すと、「どのポリシーの、どのステートメントを、どう評価して、拒否に至ったのか」をそのまま見せてくれます。推理は要りません。真犯人は名指しされます。

このハンズオンは **脱出ゲーム** です。アカウントの中に「金庫」（IAM の管理ポリシー `aws-deepcuts-vault`）があり、その説明文に修了証が刻まれています。あなたは「探偵」ロールに変身して金庫を開けよう（`iam:GetPolicy` で説明文を読もう）としますが、**5 つの鍵（拒否）** に阻まれます。手がかりは authorization ID だけ。Access Troubleshooter で真犯人を突き止め、**自分の手でポリシーを直して**、次の鍵へ進んでください。

**必要なもの**: AWS アカウント（管理者権限）と CloudShell（us-east-1）だけ。**費用**: 0 円。**所要時間**: 約 30〜45 分〔実測値: 未測定〕。

# ハンズオンのゴール

5 つの鍵は最初からすべて掛かっています。鍵 1（明示的 Deny）は IAM が最初に探すので、必ず最初に見つかります。鍵 2〜4 は同時に掛かっているので、どの順に外しても構いませんが、この README はおすすめの順（Allow を足す → 条件を満たす → 境界を広げる）で進めます。鍵が無くなったらステージ 5 で脱出です。

| ステージ | 鍵（拒否の原因） | Access Troubleshooter に出るもの | 直す場所 |
| --- | --- | --- | --- |
| 1 | **明示的 Deny ×2** — 探偵自身に掛けられた「呪い」（インラインポリシー）と、探偵に貼られた「封印」（管理ポリシー） | `EXPLICIT_DENY`。一致したステートメントに `Cursed` と `VaultSealed`（両方同時、または 1 つずつ） | 探偵ロールのポリシー |
| 2 | **暗黙の拒否** — 探偵は金庫を読む許可を 1 つも持っていない | `IMPLICIT_DENY`。一致したポリシーなし。評価されたポリシーに ID ベースポリシーが 1 枚も無い | 探偵ロール（免許をアタッチ） |
| 3 | **条件キー** — 探偵免許の Allow には `aws:PrincipalTag/clearance = top-secret` の条件がある。探偵のタグは `rookie` | `IMPLICIT_DENY`。免許は評価されたのに一致しない。コンテキストに `clearance = rookie` | 探偵ロールのタグ |
| 4 | **アクセス許可の境界** — 境界ポリシーに `iam:GetPolicy` が無い | `IMPLICIT_DENY`。評価されたポリシーに免許と境界の両方。エラー文は「no permissions boundary allows」 | 境界の管理ポリシー |
| 5 | **脱出** | （鍵は残っていない） | 金庫の説明文（修了証）が読める |

ゴールは次の 3 つを体で覚えることです。

1. `AccessDenied` のメッセージから **authorization ID** を見つけて、Access Troubleshooter に渡せる
2. 応答の「判定」「一致したポリシー」「評価されたポリシー」「リクエストコンテキスト」を見て、真犯人を名指しできる
3. IAM の評価の順番 — **① 明示的 Deny があれば即拒否 → ② 許可を与える層（ID ベースポリシーなど）に Allow が要る → ③ 許可を絞る層（境界・セッションポリシー・SCP）にも Allow が要る** — が、応答の形そのものに表れていることが分かる

# ハンズオン手順

以降の手順は、ハンズオン用に用意した AWS アカウントで実施してください。

## 構築するアーキテクチャ

![構成図](img/architecture.png)

- `setup.sh` が、金庫（IAM 管理ポリシー。説明文に修了証）、探偵ロール、探偵免許（管理ポリシー。まだアタッチされていない）、アクセス許可の境界、そして 5 つの鍵を仕込みます。
- あなたは `source ./detective.sh` で探偵に変身して金庫に挑み、`source ./admin.sh` で管理者に戻って真犯人を調べ、ポリシーを直します。
- authorization ID の照会は **管理者であるあなた** の権限で行います。探偵には `iam:GetRequestAuthorizationDetails` を与えていません（探偵は自分がなぜ拒否されたか調べられない、という設計です）。

## 前提条件

- AWS CloudShell を **バージニア北部（us-east-1）** で開くこと。`aws`（v2.36.31 以降）と `python3` を使います
- ルートユーザーではなく、**IAM ユーザーまたは IAM Identity Center のユーザー** でサインインしていること（ルートユーザーは `sts:AssumeRole` を呼べないので、探偵に変身できません）
- 実行する IAM プリンシパルに、IAM ロール／ポリシーの作成・変更・削除、作成したロールへの `sts:AssumeRole`、そして `iam:GetRequestAuthorizationDetails` の権限があること（`AdministratorAccess` 相当で実施するのが簡単です）
- Access Troubleshooter をコンソールで見る場合は、同じプリンシパルでマネジメントコンソールにサインインしていること
- （手元の PC で行う場合）認証情報は環境変数（`AWS_ACCESS_KEY_ID` など）ではなく、プロファイル（`~/.aws/credentials` や SSO）で設定してください。`detective.sh` / `admin.sh` は環境変数の認証情報を消して探偵⇄管理者を切り替えます

AWS CLI のバージョンは `aws --version` で確認できます。

<details>
<summary>AWS CLI が古い場合（ホームディレクトリに最新版を入れる）</summary>

CloudShell の AWS CLI は、最新版から数バージョン遅れていることがあります。ホームディレクトリ（`$HOME`。CloudShell では永続します）に最新版を入れれば、管理者権限なしで更新できます。

```bash
curl -sS https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip \
 && unzip -q -o /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install --install-dir "$HOME/.local/aws-cli" --bin-dir "$HOME/.local/bin" --update \
 && export PATH="$HOME/.local/bin:$PATH" && aws --version
```

`export PATH=...` は、新しい CloudShell のタブを開くたびに実行してください。
</details>

<details>
<summary>最小権限に近い IAM ポリシー例（実行者用）</summary>

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AccessTroubleshooter",
      "Effect": "Allow",
      "Action": "iam:GetRequestAuthorizationDetails",
      "Resource": "*"
    },
    {
      "Sid": "DetectiveRole",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
        "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
        "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary",
        "sts:AssumeRole"
      ],
      "Resource": "arn:aws:iam::*:role/aws-deepcuts-detective"
    },
    {
      "Sid": "ManagedPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy", "iam:GetPolicy", "iam:DeletePolicy", "iam:TagPolicy", "iam:ListEntitiesForPolicy",
        "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions", "iam:GetPolicyVersion", "iam:SetDefaultPolicyVersion"
      ],
      "Resource": ["arn:aws:iam::*:policy/aws-deepcuts-detective-boundary", "arn:aws:iam::*:policy/aws-deepcuts-detective-license", "arn:aws:iam::*:policy/aws-deepcuts-sealed", "arn:aws:iam::*:policy/aws-deepcuts-vault"]
    },
    {
      "Sid": "Identity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```
</details>

## ゲームのルール

1. 金庫を開けるのは **探偵**（`source ./detective.sh`）、調べて直すのは **管理者**（`source ./admin.sh`）です。プロンプトの先頭が `🕵️ 探偵 $` なら探偵、元に戻っていれば管理者です。
2. 探偵ロールに `"Action": "*"` や `iam:*` を足すのは禁止です（鍵を全部まとめて壊せますが、何も学べません）。
3. 各ステージの「ヒント」は、まず Access Troubleshooter を読んでから開いてください。

## 1 ステージの流れ

この 4 手を、鍵が無くなるまでくり返します。

1. `source ./detective.sh` で探偵になり、金庫を開けてみる → `AccessDenied` と **authorization ID** が出る
2. `source ./admin.sh` で管理者に戻り、Access Troubleshooter（コンソール、または CLI + `explain.py`）で真犯人を調べる
3. 管理者のまま、ポリシーやタグを直す（ヒントの `aws iam ...` コマンド、またはコンソール）
4. 1 に戻る

## １．事前準備（金庫と 5 つの鍵を仕込む）

```bash
# CloudShell を「バージニア北部（us-east-1）」で開いてから実行
# このリポジトリをクローン
git clone https://github.com/AWS-Deep-Cuts/aws-iam-toolbox
cd aws-iam-toolbox/hands-on

# セットアップスクリプトの実行
bash ./setup.sh

# 以下の文言が表示されればセットアップ成功です
# ✅ セットアップが完了しました！
```

setup.sh が作るもの:

| リソース | 役割 |
| --- | --- |
| 顧客管理ポリシー `aws-deepcuts-vault` | 金庫。**説明文（Description）に修了証** が書かれている。読むには `iam:GetPolicy` が要る |
| 顧客管理ポリシー `aws-deepcuts-detective-boundary` | 探偵のアクセス許可の境界。`iam:ListPolicies` はあるが **`iam:GetPolicy` が無い**（鍵 4） |
| IAM ロール `aws-deepcuts-detective` | 探偵。タグ `clearance=rookie`（鍵 3）、インラインポリシー `aws-deepcuts-cursed`（`Cursed`: 金庫への `iam:GetPolicy` の明示的 Deny。鍵 1） |
| 顧客管理ポリシー `aws-deepcuts-sealed`（探偵にアタッチ済み） | 封印。「金庫を開けてはならない」と書かれた札（`VaultSealed`: 金庫への `iam:GetPolicy` の明示的 Deny。鍵 1）。金庫ではなく **探偵に貼られている** |
| 顧客管理ポリシー `aws-deepcuts-detective-license` | 探偵免許。**まだアタッチされていない**（鍵 2）。金庫への `iam:GetPolicy` を Allow するが、条件 `aws:PrincipalTag/clearance = top-secret` 付き（鍵 3） |

## ２．探偵になって、金庫を開けてみる

```bash
source ./detective.sh
# 🕵️  探偵になりました: arn:aws:sts::123456789012:assumed-role/aws-deepcuts-detective/detective-...

aws iam get-policy --policy-arn "${VAULT_ARN}" --query Policy.Description --output text
```

（`VAULT_ARN` は `detective.sh` が読み込んでいます。setup.sh の最後にも表示されます）

```text
# 期待する出力（1 行で長く表示されます。右端まで読んでください。ID とアカウントは例です）
An error occurred (AccessDenied) when calling the GetPolicy operation: User: arn:aws:sts::123456789012:assumed-role/aws-deepcuts-detective/detective-123456 is not authorized to perform: iam:GetPolicy on resource: policy arn:aws:iam::123456789012:policy/aws-deepcuts-vault with an explicit deny in an identity-based policy. Go to https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/authorization-details/4q9znmckeu91fue10fy83dmze for complete details, or call the GetRequestAuthorizationDetails API with the following authorization id: 4q9znmckeu91fue10fy83dmze
```

> **この観点で確かめること**
> - **やること**: 探偵として金庫の説明文を読もうとし、エラーメッセージを **最後まで** 読みます。
> - **期待する結果**: `AccessDenied` です。メッセージには従来どおり「`... is not authorized to perform: iam:GetPolicy on resource: ... with an explicit deny in an identity-based policy`」という説明があり（管理ポリシーが原因と判定されたときは、その ARN が続くこともあります）、その続きに Access Troubleshooter を開くコンソールのリンクと **authorization ID** が含まれています。
> - **ここから分かること**: ID は、IAM がこの拒否を評価したときの記録への参照です。ID だけでは何も分かりません。`iam:GetRequestAuthorizationDetails` 権限を持つ人（= 管理者のあなた）が照会して、初めて中身が見えます。従来のメッセージは「ID ベースポリシーの明示的 Deny」（せいぜいポリシー ARN 1 つまで）しか教えてくれません。Access Troubleshooter は、評価したポリシーとステートメントを全部見せてくれます。

## ３．真犯人を調べる

方法は 2 つあります。どちらも同じ情報です。

**(a) コンソール（おすすめ）**: エラーメッセージ内のリンクを、管理者でサインインしたブラウザで開きます。Access Troubleshooter の画面に、評価されたアクションとリソース、判定（`EXPLICIT_DENY` / `IMPLICIT_DENY`）、一致したポリシーとステートメント、評価対象になったポリシーの一覧、リクエストコンテキストが表示されます（画面構成はプレビュー中のため変わる可能性があります）。

**(b) CLI**: 管理者に戻って API を呼び、同梱の `explain.py` で読み解きます。

```bash
source ./admin.sh
aws iam-toolbox get-request-authorization-details --authorization-id <ID> --region us-east-1 --output json > evidence.json
python3 explain.py evidence.json
```

> **Note**: 拒否の直後は `ResourceNotFoundException` になることがあります。数秒待って再実行してください。詳細は拒否から 24 時間は保持されます。

`explain.py` は、各評価について「判定」「一致したポリシーとステートメント（Sid）」「評価されたポリシーの種類」を並べ、最後に **「読み方」** として真犯人の推定を 1 行で出します。

## ４．鍵を外す

### ステージ 1 — 明示的 Deny が 2 つ

```text
# explain.py の出力例〔実測値: 未測定。著者が実行後に差し替え〕
[1] iam:GetPolicy  on  arn:aws:iam::123456789012:policy/aws-deepcuts-vault
    判定: EXPLICIT_DENY — 明示的 Deny
    一致: ID ベースポリシー（インライン）  inline:xxxxxxxx
          ステートメント Sid='Cursed' → DENY
    一致: ID ベースポリシー（管理ポリシー）  arn:aws:iam::123456789012:policy/aws-deepcuts-sealed
          ステートメント Sid='VaultSealed' → DENY
    → 読み方: 明示的 Deny が勝っています。真犯人: ID ベースポリシー の Sid='Cursed'、ID ベースポリシー の Sid='VaultSealed'
```

> **このステージで確かめること**
> - **やること**: 最初の拒否の評価結果を読みます。
> - **期待する結果**: 判定は `EXPLICIT_DENY`。一致したステートメントは、インラインポリシー `aws-deepcuts-cursed` の Sid `Cursed` と、管理ポリシー `aws-deepcuts-sealed` の Sid `VaultSealed` です。インラインポリシーは `inline:` で始まる識別子、管理ポリシーは ARN で表示されます。2 つが同時に並ぶか、1 つずつ名指しされるかは実機で確かめてください〔実測値: 未測定〕。1 つしか出なかった場合は、それを外してもう一度挑むと、もう 1 つが名指しされます（Deny は 1 つでも残っていれば勝ちます）。
> - **ここから分かること**: IAM は **明示的 Deny を最初に探し、1 つでもあれば他のすべてに優先** します。探偵免許があってもなくても、この 2 つがある限り金庫は開きません。従来のエラーメッセージは「ID ベースポリシーに明示的 Deny がある」としか言いません。Access Troubleshooter は、同じ ID ベースポリシーの中でも **呪い（インライン）と封印（管理ポリシー）を、Sid まで別々に名指し** します。

<details>
<summary>ヒント（直し方の例）</summary>

```bash
source ./admin.sh
source ./resource-ids.env   # ROLE_NAME / SEALED_ARN などを読み込む
# 呪い（インラインポリシー）を解く
aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${CURSE_POLICY_NAME}"
# 封印（管理ポリシー）を外す。封印は金庫ではなく、探偵ロールの「アクセス許可」タブにあります
aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${SEALED_ARN}"
```
IAM コンソール（ロール → アクセス許可タブ）から消しても構いません。
</details>

直したら、`source ./detective.sh` で探偵に戻って再挑戦してください（以降のステージも同じです）。

### ステージ 2 — 暗黙の拒否

> **このステージで確かめること**
> - **やること**: 2 回目の拒否を調べます。
> - **期待する結果**: 判定は `IMPLICIT_DENY`。一致したポリシーは **ありません**。評価されたポリシーには境界（`PERMISSIONS_BOUNDARY`）だけが並び、ID ベースポリシーは 1 枚もありません。
> - **ここから分かること**: Deny が無くなっても、**Allow が無ければ拒否** です。暗黙の拒否は「一致したものが無い」ことの結果なので、犯人を名指しできません。Access Troubleshooter は「付いていないポリシー」のことは知りません。評価されたポリシーに **ID ベースポリシーが 1 枚も無く、境界しか無い** ことが「探偵は何も持っていない」という手がかりです。setup.sh が用意した探偵免許 `aws-deepcuts-detective-license` を渡しましょう（境界が気になった人は、ステージ 4 で戻ってきます）。

<details>
<summary>ヒント（直し方の例）</summary>

```bash
source ./admin.sh
source ./resource-ids.env
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${LICENSE_ARN}"
```
</details>

### ステージ 3 — 条件キー

> **このステージで確かめること**
> - **やること**: 3 回目の拒否を調べます。**リクエストコンテキスト** に注目してください。
> - **期待する結果**: 判定は `IMPLICIT_DENY` のまま。評価されたポリシーに探偵免許（ID ベースポリシー）が含まれているのに、一致していません。リクエストコンテキスト（または評価ごとの context）に `aws:PrincipalTag/clearance = rookie` が入っているはずです〔実測値: 未測定〕。見当たらなければ、`aws iam list-role-tags --role-name aws-deepcuts-detective` で探偵のタグを確認してください。
> - **ここから分かること**: ステートメントの `Condition` が満たされないと、そのステートメントは **無かったのと同じ** です。免許を読むと `aws:PrincipalTag/clearance` が `top-secret` のときだけ Allow、と書いてあります。リクエストコンテキストは「このリクエストで条件キーにどんな値が入っていたか」の記録なので、条件絡みの拒否はここを見れば一発です。

<details>
<summary>ヒント（直し方の例）</summary>

```bash
source ./admin.sh
source ./resource-ids.env
aws iam tag-role --role-name "${ROLE_NAME}" --tags Key=clearance,Value=top-secret
```
直したら、念のため `source ./detective.sh` で**探偵になり直して**ください（セッションを取り直せば、タグの変更が確実に評価に反映されます）。
</details>

### ステージ 4 — アクセス許可の境界

> **このステージで確かめること**
> - **やること**: 4 回目の拒否を調べます。今回は、エラーメッセージの本文にも注目してください。
> - **期待する結果**: 判定は `IMPLICIT_DENY`。**評価されたポリシー** に、探偵免許（`IDENTITY_BASED_POLICY`）と境界（`PERMISSIONS_BOUNDARY`）の両方が並びます。リクエストコンテキストの `clearance` は `top-secret` に変わっているので、免許の条件は満たされています。エラーメッセージの本文も「`because no permissions boundary allows the iam:GetPolicy action`」に変わっているはずです。API の仕様上、暗黙の拒否では「一致したポリシー」が表示されないことがあります。表示される場合は、免許の `OpenVaultWithClearance` が `ALLOW` として出ます〔実測値: 未測定〕。
> - **ここから分かること**: 「誰も Deny していないし、免許の条件も満たしているのに、拒否される」。これが境界です。アクセス許可の境界は **許可を与える層ではなく、許可の上限を決める層** なので、境界に `iam:GetPolicy` が無ければ、ID ベースポリシーの Allow は無効です。従来のメッセージも「境界が原因」とは教えてくれますが、「免許は条件込みで評価されていた」「境界に何が評価されたか」までは分かりませんでした。Access Troubleshooter なら、境界ポリシーの ARN と免許の両方が評価されたことまで見えます。

<details>
<summary>ヒント（直し方の例）</summary>

```bash
source ./admin.sh
source ./resource-ids.env
aws iam create-policy-version --policy-arn "${BOUNDARY_ARN}" --set-as-default --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DetectiveBoundary",
    "Effect": "Allow",
    "Action": ["iam:ListPolicies", "iam:GetPolicy", "sts:GetCallerIdentity"],
    "Resource": "*"
  }]
}'
```
境界そのものを外す（`aws iam delete-role-permissions-boundary`）のも正解です。
</details>

### ステージ 5 — 脱出

```bash
source ./detective.sh
aws iam get-policy --policy-arn "${VAULT_ARN}" --query Policy.Description --output text
```

```text
# 期待する出力（アカウント ID と日付はあなたのもの）
[修了証] IAM 脱出ゲーム (AWS Deep Cuts) - あなたは 5 つの鍵 (明示的 Deny x2, 暗黙の拒否, 条件キー, アクセス許可の境界) を authorization ID と IAM Access Troubleshooter で解き明かし, 金庫を開けました. 発行: アカウント 123456789012 / 2026-10-29. 次の一歩: 本物の AccessDenied に出会ったら, まずエラーメッセージの中の authorization ID を探してください. 真犯人は, もう隠れられません.
```

修了証が表示されたら脱出成功です。おめでとうございます！

### 裏ボス（任意）— セッションポリシー

```bash
source ./detective.sh --disguise
aws iam get-policy --policy-arn "${VAULT_ARN}" --query Policy.Description --output text
```

> **このステージで確かめること**
> - **やること**: `--disguise` 付きで探偵に変身し、もう一度金庫を開けます。
> - **期待する結果**: 再び `EXPLICIT_DENY`。一致したのは `SESSION_POLICY` の Sid `Disguise` です。
> - **ここから分かること**: `sts:AssumeRole` のときに渡した **セッションポリシー** は、ロールに付いているどのポリシーにも書かれていないのに拒否を生みます。「ロールのポリシーをいくら見ても犯人がいない」ケースの代表です。Access Troubleshooter なら、ポリシーの種類ごと名指しされます。`detective.sh` を読むと、何をしているか分かります。

## ５．後片付け

遊び終わったら、リソースを削除しましょう。**探偵のままでは削除できない**ので、先に管理者に戻ります。

CloudShell で以下のコマンドを実行することで、今回作成したリソースを綺麗に削除することができます！

```bash
cd ~/aws-iam-toolbox/hands-on   # どこにいても大丈夫なように、絶対パスで移動
source ./admin.sh                # 探偵のままでは削除できません
bash ./cleanup.sh

# 以下の文言が表示されればクリーンアップ成功です
# ✅ すべてのリソースの削除が完了しました！

cd ~
sudo rm -rf aws-iam-toolbox
```

## トラブルシューティング

| 表示されるエラー | 主な原因 | 対処 |
| -- | -- | -- |
| `iam-toolbox コマンドに対応していません` | AWS CLI が 2.36.31 より古い | [前提条件](#前提条件) の手順で AWS CLI v2 の最新版を `$HOME` 配下にインストールする |
| `source ./detective.sh` が `AccessDenied` | 実行者に `sts:AssumeRole` が無い、ルートユーザーで実行している、またはロール作成直後で伝播していない | IAM ユーザー／Identity Center ユーザーで実行する。権限を確認する。10〜20 秒待って再実行する |
| 直したはずなのに同じ拒否になる | IAM の変更の伝播待ち、または探偵のセッションが古い（タグの変更など） | 10 秒待つ。`source ./detective.sh` で探偵になり直す |
| エラーメッセージに authorization ID が無い | 対象外のサービス／API（2026 年 10 月時点では主に IAM の API が対象）、または ID が付与されなかったケース | このゲームでは `aws iam get-policy` を使う |
| `ResourceNotFoundException`（照会時） | 反映前に照会した、または拒否と違うリージョンで照会した | 数秒待って再実行する。`--region us-east-1` を確認する |
| `get-request-authorization-details` が `AccessDeniedException` | 探偵のまま照会している、または実行者に `iam:GetRequestAuthorizationDetails` が無い | `source ./admin.sh` で管理者に戻る。権限を確認する |
| `cleanup.sh` が `探偵のままです` | 環境変数に探偵の認証情報が残っている | `source ./admin.sh` を実行してから再実行する |
| `source ./admin.sh` の後に管理者の認証情報が無い（手元の PC） | 認証情報を環境変数で設定していた | プロファイル（`~/.aws/credentials` や SSO）で設定し直す。CloudShell ならこの問題は起きません |
| `setup.sh` が `既に存在します` | 前回のリソースが残っている | `bash ./cleanup.sh` を実行してから `setup.sh` をやり直す |

## 参考リンク

- [Troubleshoot access denied error messages with authorization ID (Preview)](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_access-denied-authorization-id.html)
- [GetRequestAuthorizationDetails - IAM Toolbox API Reference](https://docs.aws.amazon.com/iam-toolbox/latest/APIReference/API_GetRequestAuthorizationDetails.html)
- [Policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [Troubleshoot access denied error messages](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_access-denied.html)
- [AWS CLI `iam-toolbox` リファレンス](https://docs.aws.amazon.com/cli/latest/reference/iam-toolbox/)
- [AWS CloudShell で AWS CLI を手動でインストールする](https://docs.aws.amazon.com/cloudshell/latest/userguide/vm-specs.html)

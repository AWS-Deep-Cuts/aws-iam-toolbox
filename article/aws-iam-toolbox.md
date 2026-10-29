---
title: 【AWS Deep Cutsシリーズ】IAM Access Troubleshooterって知ってる？AccessDeniedの「真犯人」を名指しで突き止めよう！
tags: AWS AWSDeepCuts IAM セキュリティ トラブルシューティング
author: kenken38
slide: false
---
:::note info
AWS Deep Cuts の GitHub はこちらです。
https://github.com/AWS-Deep-Cuts/AWS-Deep-Cuts
:::

# AWS Deep Cutsとは？
AWS Deep Cutsは、AWS の最新のサービスやニッチな機能、または高度にアカデミックな知識を要求するサービスなど、多くの人が知らない 『隠れた名曲 = **Deep Cuts**』 を深くまで掘り下げる技術シリーズです。

このようなサービスはWeb情報も少なく、初学者は気軽にキャッチアップできないのが実情です。

そこで AWS Deep Cuts シリーズでは、**前提知識も含めた分かりやすいサービス解説** と **手順通りに進めれば誰でも再現できるハンズオン** を提供します！

# そもそもAccessDeniedはなぜ分かりにくい？
AWS を使っていて、いちばん見たくないのに、いちばんよく見る単語。それが `AccessDenied` です。

厄介なのは、**犯人が分からない** ことです。AWS がリクエストを許可するかどうかは、1 枚のポリシーで決まるのではありません。ID ベースポリシー、リソースベースポリシー、アクセス許可の境界、セッションポリシー、SCP（サービスコントロールポリシー）、RCP（リソースコントロールポリシー）、VPC エンドポイントポリシー……。全部知らなくて大丈夫です。「ポリシーは何種類もあって、**決まった順番で評価される**」ことだけ押さえてください。その結果が `AccessDenied` で、どこで止まったのかは結果からは分かりません。

:::note info
身近なたとえで言うと、ビルの入館を断られたようなものです。警備員（SCP）が止めたのか、受付（リソースベースポリシー）が止めたのか、あなたの社員証の権限（ID ベースポリシー）が足りないのか、上司が「この人は 3 階までしか入れない」と決めている（アクセス許可の境界）のか。「入れません」としか言われなければ、全員に聞いて回るしかありません。
:::

これまで、AWS のエラーメッセージは少しずつ親切になってきました。

| 時期 | エラーメッセージで分かること |
| --- | --- |
| 2021 年 11 月〜 | 「`because no identity-based policy allows the ... action`」「`with an explicit deny in a service control policy`」のように、**どの種類のポリシーが原因か** |
| 2026 年 1 月〜 | SCP・RCP・ID ベースポリシー・セッションポリシー・アクセス許可の境界について、**原因になったポリシーの ARN** |
| 2026 年 8 月〜（プレビュー） | **authorization ID**。これを照会すると、評価の過程そのものが見える |

ただし、従来のメッセージには限界がありました。複数の種類のポリシーが拒否していても **1 種類しか載りません** し、「ID ベースポリシーは許可していたのに、境界に無いから拒否された」のような、拒否に至る途中経過も載りません。

# IAM Access Troubleshooterとは？
IAM Access Troubleshooter は、拒否された 1 つのリクエストについて、**IAM がどのポリシーをどう評価してその結論に至ったのか** を見せてくれる機能です。2026 年 8 月下旬（AWS CLI / SDK への API 追加は 8 月 25 日）からプレビューで提供されています。

名前が 3 つ出てくるので先に整理しておきます。コンソールでは **Access Troubleshooter**、API / CLI では **IAM Toolbox**（`aws iam-toolbox get-request-authorization-details`）、必要な権限は `iam:GetRequestAuthorizationDetails`。全部同じものです。

使い方は 2 ステップです。

1. 対応する API で拒否されると、エラーメッセージに **authorization ID** と、コンソールへのリンクが付いてくる
2. そのリンクを開く（または `aws iam-toolbox get-request-authorization-details --authorization-id <ID>` を呼ぶ）と、評価の過程が表示される

```text
User: arn:aws:iam::123456789012:user/janedoe is not authorized to perform: iam:CreateInstanceProfile on resource: arn:aws:iam::123456789012:instance-profile/example with an explicit deny in an identity-based policy. Go to https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/authorization-details/4q9znmckeu91fue10fy83dmze for complete details, or call the GetRequestAuthorizationDetails API with the following authorization id: 4q9znmckeu91fue10fy83dmze
```

IAM Access Troubleshooter には、以下のような特徴があります。

- **評価の過程を、ポリシーとステートメント単位で見せる**
  判定（`ALLOW` / `EXPLICIT_DENY` / `IMPLICIT_DENY`）、一致したポリシーとステートメント（Sid）、評価対象になったすべてのポリシー、そしてリクエストコンテキスト（条件キーの値）が返ります。
- **7 種類のポリシーを区別する**
  ID ベースポリシー、リソースベースポリシー、アクセス許可の境界、セッションポリシー、SCP、RCP、VPC エンドポイントポリシー。「ロールのポリシーをいくら見ても犯人がいない」ケース（セッションポリシーや SCP）も名指しされます。
- **1 つの API 呼び出しに含まれる複数の評価が分かる**
  API ドキュメントの例は `iam:PassRole` です。たとえば将来 Lambda が対応すれば、関数作成時の `lambda:CreateFunction` と `iam:PassRole` の 2 つの評価がどちらで拒否されたか分かるようになります（2026 年 10 月時点の対応は主に IAM の API）。
- **料金はかからない**
  IAM は無料で、Access Troubleshooter にも 2026 年 10 月時点で料金表はありません。
- **制約（2026 年 10 月時点のプレビュー）**
  提供は **バージニア北部（us-east-1）のみ** で、東京リージョン（ap-northeast-1）ではまだ使えません。authorization ID が付くのは **主に IAM の API** で、他のサービスは順次対応中です。保持期間や照会の条件は、後述の「ベストプラクティス」を見てください。

# 仕組み：IAMの評価ロジックが、そのまま応答の形になっている
Access Troubleshooter の応答を理解するには、IAM がリクエストを評価する順番を知っておくと早いです。公式ドキュメントの「ポリシーの評価論理」を、ざっくり 4 段階にまとめると次のようになります。

1. **既定はすべて拒否**（暗黙の拒否）
2. **明示的 Deny が 1 つでもあれば、即拒否**。どんな Allow よりも強い
3. **許可を与える層**（ID ベースポリシー、リソースベースポリシー）のどれかに Allow が要る
4. **許可を絞る層**（SCP / RCP、アクセス許可の境界、セッションポリシー）が付いていれば、そこでも Allow されていないと拒否

（リソースベースポリシーだけで許可される場合の細かい条件は、公式ドキュメントを参照してください）

Access Troubleshooter の応答（`GetRequestAuthorizationDetails`）は、この構造を写し取った形をしています。

| 応答のフィールド | 中身 | 評価ロジックとの対応 |
| --- | --- | --- |
| `requestContext` | リクエスト全体に共通する条件キーの値（API リファレンスの例では `aws:PrincipalARN`、`aws:SourceIp`、`aws:RequestedRegion`、`aws:SecureTransport`。条件に使った `aws:PrincipalTag/...` も含まれるはずです〔実測値: 未測定〕） | 条件（`Condition`）が満たされたかどうかの材料 |
| `evaluations[]` | アクション × リソースの組ごとの評価。`action`、`resource`、`evaluatedEffect`（`ALLOW` / `EXPLICIT_DENY` / `IMPLICIT_DENY`）、`matchedPolicies[]` | 1 つの API 呼び出しに複数の評価があることがある（`iam:PassRole` など） |
| `evaluations[].matchedPolicies[]` | その評価で **一致した** ポリシーと、一致したステートメントの `sid` と効果（`ALLOW` / `DENY`） | 明示的 Deny の「真犯人」はここに名指しされる。暗黙の拒否では空 |
| `policies[]` | **評価対象になった** すべてのポリシー。`type`（7 種類）、インラインかどうか、識別子、アタッチ先 | 暗黙の拒否のときに「どこに Allow を足せばよいか」を考える材料 |

読み方のコツは 2 つです。

- **`EXPLICIT_DENY` なら、`matchedPolicies` の中の `DENY` を探す**。それが真犯人です。複数あれば全部直す必要があります。
- **`IMPLICIT_DENY` なら、犯人は「いない」**。代わりに、`policies` に並ぶポリシーの種類を見ます。ID ベースポリシーが評価されているのに全体が `IMPLICIT_DENY` なら、Allow が無いか条件が満たされていないか、または境界・セッションポリシー・SCP・RCP・VPC エンドポイントポリシーのどれか（許可を絞る層）に Allow が無いということです。条件絡みなら `requestContext` の値を見れば、どの条件が満たされなかったか分かります。

:::note warn
**authorization ID は「鍵」であって「中身」ではない**
ID はエラーメッセージに載りますが、ID だけでは何も分かりません。中身を見るには `iam:GetRequestAuthorizationDetails` の権限が要ります。拒否された本人にこの権限が無ければ、本人は自分がなぜ拒否されたか調べられません。これは、以前からある `sts:DecodeAuthorizationMessage`（EC2 などが返すエンコードされた拒否理由をデコードする API）と同じ考え方です。「デバッグのしやすさ」と「権限の構造を見せすぎないこと」を、権限で切り分けています。
:::

# IAM Access Troubleshooterの主な活用事例
- **開発者のセルフサービス**（開発者に `iam:GetRequestAuthorizationDetails` を渡す運用の場合）
  「権限が無いので付けてください」という依頼が、「管理ポリシー `deny-prod-write` の `DenyS3Write` が Deny しています」という具体的な依頼に変わります。管理者が全ポリシーを読み直す時間が減ります。
- **多層防御の設計レビュー**
  SCP・境界・セッションポリシーのように「許可を絞る層」が意図どおりに効いているかを、実際の拒否で確かめられます。
- **条件キーのデバッグ**
  `aws:PrincipalTag` や `aws:SourceIp` のような条件付きの Allow が効かないとき、`requestContext` を見れば、リクエストにどんな値が入っていたかが分かります。
- **サポートへの問い合わせ**
  authorization ID を添えれば、状況を説明する手間が減ります。

# IAM Access Troubleshooterを使う際のベストプラクティス
- **まずエラーメッセージを最後まで読む**
  authorization ID とコンソールへのリンクは、メッセージの末尾に付いています。CLI の出力は折り返されるので、見落としがちです。
- **24 時間以内に、同じリージョンで照会する**
  詳細が保持されるのは拒否から 24 時間です（API リファレンスでは「少なくとも 24 時間」）。それを過ぎると照会できないものと考えて、早めに照会します。照会は拒否が起きたリージョン（プレビュー中は us-east-1）で、同じアカウントまたは同じ Organizations 内のプリンシパルから行います。拒否の直後は記録がまだ無く `ResourceNotFoundException` になることがあるので、数秒待って再試行します。
- **`iam:GetRequestAuthorizationDetails` を誰に渡すか決めておく**
  応答には評価されたポリシーの構造やリクエストコンテキストが含まれます。開発者に渡すか、管理者だけに絞るかは組織の方針で決めましょう。
- **「拒否が正しい」こともある**
  公式ドキュメントも注意していますが、拒否は意図どおりかもしれません。セッションタグが無い、想定外のネットワーク経路から来た、というケースでは、直すべきはポリシーではなくリクエストの側です。
- **ID が付かないケースを知っておく**
  対応外のサービス／API、サービスが代行したリクエスト、匿名のリクエスト、評価したポリシーが多すぎるリクエストには ID が付きません。

# ハンズオンはこちら！
「IAM 脱出ゲーム」です。金庫（IAM ポリシー）に 5 つの鍵（明示的 Deny ×2、暗黙の拒否、条件キー、アクセス許可の境界）を掛け、探偵ロールに変身して挑みます。手がかりは authorization ID だけ。Access Troubleshooter で真犯人を突き止め、自分の手でポリシーを直して、修了証を読んでください。CloudShell だけで完結し、費用は 0 円です。

![ハンズオンの構成図](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/architecture.png)

探偵ロール（あなたが変身）が金庫（IAM ポリシー）を開けようとして拒否され、管理者のあなたが authorization ID を Access Troubleshooter に渡して真犯人を調べる、という構成です。

https://github.com/AWS-Deep-Cuts/aws-iam-toolbox

# まとめ
IAM Access Troubleshooter は、`AccessDenied` を「推理するもの」から「読むもの」に変えます。応答の形は IAM のポリシー評価ロジックそのものなので、使っているうちに評価ロジックが体に入ります。プレビュー中で制約はありますが、IAM の権限で困ったことがある人は、ぜひ一度 authorization ID を照会してみてください！

# もっと深く知りたい人へ
- **3 世代のエラーメッセージ**: エンコードされた拒否理由を `sts:DecodeAuthorizationMessage` でデコードする方式（EC2 など一部のサービス）→ 2021 年のポリシー種別付き → 2026 年 1 月の ARN 付き → authorization ID。`DecodeAuthorizationMessage` の公式ドキュメントには「認可状態の詳細は、リクエストしたユーザーが見るべきでない特権情報を含みうるためエンコードされている」とあり、authorization ID はこの問題を「ID は見せるが、中身は権限で守る」という形で解いています。
- **IAM Policy Simulator との違い**: Policy Simulator は「もし呼んだらどうなるか」を事前に試すツール（SCP は評価できるが RCP は未対応）、Access Troubleshooter は「実際に拒否されたリクエスト」の事後分析です。設計時はシミュレーター、運用時はトラブルシューター、と使い分けます。
- **CloudTrail との関係**: 拒否は CloudTrail にも `errorCode` / `errorMessage` として記録され、`errorMessage` にはエラーメッセージ全文が残るので、ID をそこから拾って照会することは今でもできます（`errorMessage` は長いと切り詰められる点に注意）。2026 年 10 月時点では ID 専用のフィールドは無く、専用フィールドが付けば事後監査はさらに楽になりそうです。

---

参考文献
1. [Troubleshoot access denied error messages with authorization ID (Preview)](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_access-denied-authorization-id.html)
1. [GetRequestAuthorizationDetails - IAM Toolbox API Reference](https://docs.aws.amazon.com/iam-toolbox/latest/APIReference/API_GetRequestAuthorizationDetails.html)
1. [Policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
1. [Troubleshoot access denied error messages](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_access-denied.html)
1. [AWS Identity and Access Management now makes it more efficient to troubleshoot access denied errors in AWS（What's New, 2021-11）](https://aws.amazon.com/about-aws/whats-new/2021/11/aws-identity-access-management-efficient-troubleshoot-error/)
1. [Access denied error messages now include additional policy details（What's New, 2026-01）](https://aws.amazon.com/about-aws/whats-new/2026/01/additional-policy-details-access-denied-error/)
1. [DecodeAuthorizationMessage - AWS STS API Reference](https://docs.aws.amazon.com/STS/latest/APIReference/API_DecodeAuthorizationMessage.html)

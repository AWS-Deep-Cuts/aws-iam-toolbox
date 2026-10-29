---
title: 【AWS Deep Cutsシリーズ】IAM Access Troubleshooterって知ってる？AccessDeniedの原因になったポリシーを特定しよう！
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

# そもそもAccessDeniedの原因はなぜ分かりにくいのか？
AWS の API を呼び出したときに、IAM（AWS Identity and Access Management）がリクエストを拒否すると、`AccessDenied` のエラーが返ります。このエラーの原因を特定するのは、簡単ではありません。IAM がリクエストを許可するかどうかは、1 つのポリシーだけでは決まらないからです。

AWS にリクエストを送る IAM ユーザーや IAM ロールを、**プリンシパル**と呼びます。ロールに切り替えると、AWS STS（AWS Security Token Service）が一時的な認証情報を発行します。この一時的な認証情報を使って行う一連の操作を、**セッション**と呼びます。セッションには、名前とタグを付けられます。

プリンシパルの権限を決めるポリシーには、次の種類があります。

| ポリシーの種類 | 設定する場所 | 役割 | 分類 |
| --- | --- | --- | --- |
| ID ベースポリシー | IAM のユーザー、グループ、ロール | そのユーザーやロールに、操作を許可または拒否する | 許可を与える |
| リソースベースポリシー | S3 バケットなどのリソース | そのリソースへの操作を、誰に許可または拒否するかを定める | 許可を与える |
| アクセス許可の境界 | IAM のユーザー、ロール | そのユーザーやロールが行える操作の上限を定める | 許可を絞る |
| セッションポリシー | ロールに切り替える API の呼び出しで渡す | そのセッションで行える操作の上限を定める | 許可を絞る |
| SCP（サービスコントロールポリシー） | AWS Organizations の組織やアカウント | アカウント内のユーザーやロールが行える操作の上限を定める | 許可を絞る |
| RCP（リソースコントロールポリシー） | AWS Organizations の組織やアカウント | アカウント内のリソースに対して行える操作の上限を定める | 許可を絞る |
| VPC エンドポイントポリシー | VPC エンドポイント | そのエンドポイントを通る操作の上限を定める | 許可を絞る |

ID ベースポリシーには、独立したポリシーとして作成して複数のユーザーやロールにアタッチできる**管理ポリシー**と、1 つのユーザーやロールの中に直接書き込む**インラインポリシー**があります。また、表の SCP と RCP を設定する AWS Organizations は、複数の AWS アカウントを 1 つの**組織**としてまとめて管理するサービスです。

これらのポリシーの種類を、すべて覚える必要はありません。押さえてほしいのは、ポリシーには「許可を与えるポリシー」と「許可を絞るポリシー」があり、IAM がそれらを決まった順序で評価して、許可か拒否かを決めることです。

ポリシーは、1 つ以上の**ステートメント**からなります。ステートメントには、許可するか拒否するかを表す Effect、対象の操作を表す Action、対象のリソースを表す Resource を書きます。必要に応じて、条件を表す Condition も書きます。Effect の値は Allow か Deny で、この記事では、この値をステートメントの**効果**と呼びます。ステートメントがリクエストに**一致する**とは、ステートメントの Action と Resource がリクエストの操作と対象に当てはまり、Condition があればその条件も満たすことを指します。

ポリシーの種類の表で「許可を与える」に分類した ID ベースポリシーにも、効果が Deny のステートメントを書けます。分類の「許可を与える」と「許可を絞る」は、そのポリシーの Allow が操作を許可するのか、許可できる範囲の上限を定めるだけなのかの違いです。

IAM がポリシーを評価する順序を簡略化すると、次の図のようになります。

![IAM がポリシーを評価する順序](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/evaluation-flow.png)

図の `EXPLICIT_DENY`・`IMPLICIT_DENY`・`ALLOW` は、後で説明する IAM Access Troubleshooter が、IAM の結論として表示する値です。

1. どれか 1 つのポリシーに、リクエストに一致する Deny のステートメントがあれば、IAM はリクエストを拒否します。これを **明示的な拒否** と呼びます。
2. Deny が無くても、許可を与えるポリシーに一致する Allow のステートメントが無ければ、IAM はリクエストを拒否します。これを **暗黙的な拒否** と呼びます。
3. 許可を与えるポリシーに一致する Allow があっても、許可を絞るポリシーが設定されている場合は、設定されている許可を絞るポリシーのそれぞれに、一致する Allow が必要です。一致する Allow が無いポリシーが 1 つでもあれば、IAM はリクエストを拒否します。これも暗黙的な拒否です。

これは簡略化した説明です。正確な順序と、リソースベースポリシーが IAM ユーザーに直接許可を与える場合などの例外は、公式ドキュメント「ポリシーの評価論理」で確認してください。

`AccessDenied` は、この評価の最終的な結果です。どのポリシーのどの段階で拒否されたのかは、この結果だけでは分かりません。

AWS は、エラーメッセージに含める情報を、次の表のように少しずつ増やしてきました。表の ARN（Amazon Resource Name）は、AWS のリソースを一意に識別するための名前です。

| 時期 | エラーメッセージで分かること |
| --- | --- |
| 2021 年 11 月〜 | 拒否の原因になったポリシーの種類が表示される。例: `with an explicit deny in a service control policy`、`because no identity-based policy allows the ... action` |
| 2026 年 1 月〜 | 同じアカウントか同じ組織の中のリクエストで、原因になったポリシーの ARN が表示される。対象は SCP、RCP、ID ベースポリシー、セッションポリシー、アクセス許可の境界 |

それでも、エラーメッセージには限界があります。複数のポリシーが拒否に関係していても、メッセージに表示されるのは 1 つのポリシーだけです。また、どのステートメントが一致したのかや、条件の評価に使われた値は、メッセージからは分かりません。条件の評価に使われた値とは、たとえばロールのタグや、送信元の IP アドレスです。

そこで、2026 年 8 月から、IAM は拒否したリクエストのエラーメッセージに **authorization ID** を付けるようになりました。authorization ID は、拒否されたリクエストを 1 件ずつ識別するための ID です。この ID で照会すると、IAM がそのリクエストをどう評価したかの記録を確認できます。この記事では、この記録を**評価の詳細**と呼びます。authorization ID で評価の詳細を照会するための機能が、次の章で説明する IAM Access Troubleshooter です。

# IAM Access Troubleshooterとは？
IAM Access Troubleshooter は、拒否された 1 つのリクエストについて、IAM がどのポリシーをどう評価したのかを表示する機能です。2026 年 8 月から、プレビューとして提供されています。公式ドキュメントによると、2026 年 10 月時点で authorization ID が付くのは、IAM の大半の API です。他のサービスへの対応は、順次進められています。

この機能は、使う場所によって名前が異なります。

| 使う場所 | 名前 |
| --- | --- |
| マネジメントコンソール | Access Troubleshooter |
| API | IAM Toolbox の `GetRequestAuthorizationDetails` |
| AWS CLI | `aws iam-toolbox get-request-authorization-details` |
| IAM ポリシーのアクション | `iam:GetRequestAuthorizationDetails` |

API と AWS CLI では、この機能は IAM Toolbox という名前で提供されています。そのため、AWS CLI のコマンドは `aws iam` ではなく `aws iam-toolbox` で始まります。一方、この API を呼び出す権限の名前は、IAM の `iam:GetRequestAuthorizationDetails` です。以降は、この機能を Access Troubleshooter と呼びます。

この記事では、評価の詳細を照会する権限と、ポリシーを修正する権限を持つ人を、**管理者**と呼びます。拒否されたプリンシパルを使っていた人と管理者は、同じ人のことも、別の人のこともあります。

拒否から照会までの流れは、次の図のとおりです。図の番号は、下の説明の番号と対応しています。

![拒否から照会までの流れ](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/troubleshooter-flow.png)

1. プリンシパルが、AWS の API を呼び出します。
2. IAM がポリシーを評価し、リクエストを拒否します。
3. IAM は、エラーメッセージに authorization ID と、Access Troubleshooter の画面へのリンクを付けて返します。
4. IAM は、エラーを返す処理とは別に、評価の詳細を、拒否が起きたリージョンに記録します。記録が終わるまでに、少し時間がかかることがあります。
5. 管理者は、リンクを開くか API を呼び出して、authorization ID で評価の詳細を照会します。
6. Access Troubleshooter は、評価の詳細を、コンソールでは画面に表示し、API では応答として返します。管理者は、その内容を確認します。評価の詳細には、条件の評価に使われた値の一覧である**リクエストのコンテキスト**、IAM の結論である**判定**、リクエストに一致したポリシーとステートメント、評価の対象になったすべてのポリシーの 4 つが含まれます。

対応している API で拒否されると、エラーメッセージの最後に、コンソールの URL と authorization ID が付きます。次の例は、ハンズオンで表示されるエラーメッセージの形です。authorization ID、アカウント ID、セッション名は説明用の値です。

```text
User: arn:aws:sts::111122223333:assumed-role/aws-deepcuts-handson-role/handson-153012 is not authorized to perform: iam:GetPolicy on resource: policy arn:aws:iam::111122223333:policy/aws-deepcuts-certificate with an explicit deny in an identity-based policy. Go to https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/authorization-details/0example1authorization2id for complete details, or call the GetRequestAuthorizationDetails API with the following authorization id: 0example1authorization2id
```

原因が管理ポリシーの場合は、`identity-based policy` の後ろに `: <ポリシーの ARN>` が付くことがあります。インラインポリシーには ARN が無いため、ARN は付きません。メッセージの各部分の意味は、次の図のとおりです。

![AccessDenied のエラーメッセージの読み方](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/error-message.png)

Access Troubleshooter には、以下のような特徴があります。

- **評価の詳細をポリシーとステートメントの単位で表示する**
  リクエストのコンテキスト、判定、一致したポリシーとステートメントの Sid、評価の対象になったすべてのポリシーを表示します。Sid（Statement ID）は、ポリシーの中のステートメントを区別するために付ける ID です。
- **7 種類のポリシーを区別する**
  ID ベースポリシー、リソースベースポリシー、アクセス許可の境界、セッションポリシー、SCP、RCP、VPC エンドポイントポリシーを区別して表示します。ロールの設定を確認しても見つからないセッションポリシーや SCP による拒否も、ポリシーの種類と一緒に確認できます。
- **アクションとリソースの組ごとに判定を表示する**
  API の仕様では、応答の `evaluations` は、アクションとリソースの組ごとの評価のリストです。1 つの API の呼び出しで複数のアクションが評価された場合は、組ごとに判定が表示されます。
- **固有の料金は公開されていない**
  IAM は追加料金なしで使えます。Access Troubleshooter に固有の料金は、2026 年 10 月時点で、ドキュメントにも価格表にも載っていません。

2026 年 10 月時点のプレビューには、次の制約があります。

- 2026 年 8 月 25 日の AWS SDK と AWS CLI のリリースノートによると、プレビューを提供するリージョンは、バージニア北部（us-east-1）だけです。公式ドキュメントは、対応する API とリージョンを順次広げていると説明しています。2026 年 10 月時点で、東京リージョンでの提供は発表されていません。
- 公式ドキュメントによると、対応している API でも、次のリクエストには authorization ID が付かないことがあります。
  - 評価の対象になるポリシーが多すぎて、IAM が評価の詳細を記録できないリクエスト
  - AWS のサービスがプリンシパルの代わりに行ったリクエスト
  - 認証情報を使わない匿名のリクエスト

# 仕組み：評価の詳細の読み方
この章では、評価の詳細に何が含まれ、拒否の原因をどの順に探すのかを説明します。説明には、API の応答の JSON を使います。公式ドキュメントによると、コンソールの画面でも、アクションとリソースの組ごとの評価を確認できます。

管理者は、次のコマンドで、エラーメッセージの authorization ID を指定して評価の詳細を取得します。ID は、前の章のエラーメッセージの例と同じ説明用の値です。

```bash
aws iam-toolbox get-request-authorization-details \
  --authorization-id 0example1authorization2id --region us-east-1
```

次の図は、応答の JSON を説明用に短くした例です。

![評価の詳細の 4 つの部分](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/response-anatomy.png)

| 応答の項目 | この記事での呼び名 | 内容 | 原因を調べるときの使い方 |
| --- | --- | --- | --- |
| `requestContext` | リクエストのコンテキスト | リクエスト全体に共通する条件キーとその値。条件キーは、ポリシーの Condition で使うキーで、`aws:SourceIp` などがある | Condition を満たしたかどうかを確かめるときに確認する |
| `evaluations[].evaluatedEffect` | 判定 | アクションとリソースの組ごとの結果。`ALLOW`、`EXPLICIT_DENY`、`IMPLICIT_DENY` のいずれか | 明示的な拒否か、暗黙的な拒否かを確かめる |
| `evaluations[].matchedPolicies` | 一致したポリシー | 評価で一致したポリシーと、一致したステートメントの Sid と効果 | 明示的な拒否の原因を確かめる。API リファレンスによると、暗黙的な拒否では一致したポリシーは返らない |
| `policies` | 評価されたポリシー | 評価の対象になったすべてのポリシー。種類、インラインかどうか、アタッチされている先 | 暗黙的な拒否のときに、どの種類のポリシーに Allow が足りないかを確かめる |

応答には、ポリシーの本文は含まれません。ステートメントの中身は、IAM コンソールでポリシーを開いて確認します。

判定によって、原因の探し方が変わります。

![判定ごとの原因の探し方](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/how-to-read.png)

- **判定が `EXPLICIT_DENY` のとき**
  一致したポリシーの中から、効果が `DENY` のステートメントを探します。そのステートメントが拒否の原因です。複数あれば、すべてが原因です。
- **判定が `IMPLICIT_DENY` のとき**
  一致したポリシーは空になるため、評価の詳細には、原因のポリシーが表示されません。代わりに、次の表を上から順に確かめます。

| 順序 | 確かめること | 当てはまらない場合の原因 | 修正すること |
| --- | --- | --- | --- |
| 1 | 評価された ID ベースポリシーの中に、その操作を許可する Allow のステートメントがあるか。評価の詳細にはポリシーの本文が無いため、IAM コンソールでポリシーを開いて確かめる | 許可するポリシーが無い | その操作を許可する Allow のステートメントを持つポリシーをアタッチするか、ポリシーに追加する |
| 2 | ID ベースポリシーの Allow の Condition を、リクエストのコンテキストの値が満たしているか | 条件を満たしていない | IAM コンソールでポリシーの Condition を確認し、条件か、リクエストの側を修正する |
| 3 | 許可を絞るポリシーにも、同じ操作の Allow があるか | 許可を絞るポリシーによる拒否 | そのポリシーに Allow を追加する |

エラーメッセージの拒否の理由も、どの段階で拒否されたかを判断する根拠になります。たとえば、拒否の理由が `because no identity-based policy allows` であれば、原因は上の表の順序 1 か 2 で見つかります。`because no permissions boundary allows` であれば、表の順序 3 で確かめるアクセス許可の境界が原因です。

:::note info
**authorization ID だけでは評価の詳細を確認できない**
authorization ID はエラーメッセージに表示されますが、評価の詳細を照会するには `iam:GetRequestAuthorizationDetails` の権限が必要です。拒否されたユーザーやロールにこの権限が無ければ、そのユーザーやロールの認証情報では、評価の詳細を照会できません。また、2026 年 10 月時点では、この権限を許可するポリシーの Resource で、照会できるリクエストの範囲を限定することはできません。この権限を持つユーザーやロールは、同じアカウントか同じ組織の中であれば、他のユーザーやロールが受けた拒否についても、評価の詳細を照会できます。
:::

# IAM Access Troubleshooterの主な活用事例
- **開発者からの権限の依頼を具体的にする**
  開発者に照会の権限を付与しておけば、開発者からの依頼は「権限が無いので付けてください」から、「管理ポリシー `deny-prod-iam-write` の Sid `DenyRoleChanges` に拒否されています。このステートメントの対象から、開発用のロールを外してください」のような具体的な依頼に変わります。管理者が、すべてのポリシーを読み直す手間が減ります。ポリシーと Sid の名前は、説明用の例です。
- **多層の権限設計が意図どおりに機能しているかを確かめる**
  SCP、アクセス許可の境界、セッションポリシーのような許可を絞るポリシーが、意図どおりに機能しているかを、実際の拒否で確認できます。
- **条件キーの実際の値を確かめる**
  `aws:SourceIp` などを条件に使った Allow が適用されないときに、リクエストのコンテキストで、リクエストに含まれていた実際の値を確認できます。
- **照会を管理者に引き継ぐ**
  拒否されたユーザーやロールに照会の権限が無くても、そのユーザーやロールを使っていた人が authorization ID を管理者に伝えれば、照会の権限を持つ管理者が同じ評価の詳細を開けます。照会できるのは、同じアカウントか同じ組織の中で起きた拒否です。拒否から 24 時間以内であれば照会できます。

# IAM Access Troubleshooterを使う際のベストプラクティス
- **エラーメッセージを最後まで読む**
  authorization ID とコンソールの URL は、メッセージの最後にあります。CLI ではメッセージが長く表示されるため、見落としやすくなります。
- **拒否から 24 時間以内に同じリージョンで照会する**
  API リファレンスによると、評価の詳細は、拒否から少なくとも 24 時間は照会できます。それより後も照会できるとは限らないため、拒否から 24 時間以内に照会します。照会は、拒否が起きたリージョンで、同じアカウントか同じ組織のユーザーやロールから行います。評価の詳細は、エラーを返す処理とは別に、少し遅れて記録されます。そのため、拒否の直後に照会すると、`ResourceNotFoundException` が返ることがあります。その場合は、少し待ってから照会し直します。
- **照会の権限を誰に付与するかを決めておく**
  評価の詳細には、ポリシーの構成や、リクエストのコンテキストが含まれます。「仕組み：評価の詳細の読み方」の章の注記で説明したとおり、照会の権限を持つユーザーやロールは、他のユーザーやロールが受けた拒否についても、評価の詳細を照会できます。開発者にも付与するか、管理者だけにするかを、社内の方針として決めておきます。
- **意図どおりの拒否もあることを忘れない**
  拒否の原因は、ポリシーの誤りとは限りません。たとえば、ロールに切り替えるときにセッションに付けるはずのタグ、つまりセッションタグが付いていない場合や、想定外のネットワークからアクセスしている場合は、ポリシーは意図どおりに拒否しています。このとき修正すべきなのは、ポリシーではなく、リクエストの側です。

# ハンズオンはこちら！
ハンズオンでは、4 種類の拒否の原因を、ステージとして 1 つずつ特定して解消します。authorization ID が付くのは、主に IAM の API です。そのため、このハンズオンでは、修了証を管理ポリシーの説明文に書いておき、その説明文を IAM の `GetPolicy` API で読み取ります。あなたは、ハンズオン用の IAM ロールに切り替えて、修了証の読み取りを試します。

事前準備のスクリプトは、このロールで読み取りが拒否される原因を 4 種類用意します。拒否されるたびに、あなたは Access Troubleshooter で原因を特定し、IAM コンソールで設定を修正します。CloudShell とマネジメントコンソールだけで実施でき、作成するのは IAM のロールとポリシーだけです。

![ハンズオンの構成図](https://github.com/AWS-Deep-Cuts/aws-iam-toolbox/raw/main/img/architecture.png)

図の手順の番号は、ハンズオンの README の手順の番号です。

https://github.com/AWS-Deep-Cuts/aws-iam-toolbox

# まとめ
Access Troubleshooter を使うと、明示的な拒否では原因のポリシーとステートメントを、暗黙的な拒否では評価されたポリシーとリクエストのコンテキストを確認でき、`AccessDenied` の原因を絞り込めます。評価の詳細を、IAM がポリシーを評価する順序と照らし合わせて読むと、評価の仕組みの理解も深まります。プレビューで制約はありますが、IAM の権限で困ったことがある方は、ぜひ一度 authorization ID を照会してみてください！

---

参考文献
1. [authorization ID を使ってアクセス拒否のエラーを調べる（Troubleshoot access denied error messages with authorization ID (Preview)）](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_access-denied-authorization-id.html)
1. [GetRequestAuthorizationDetails の API リファレンス（IAM Toolbox API Reference）](https://docs.aws.amazon.com/iam-toolbox/latest/APIReference/API_GetRequestAuthorizationDetails.html)
1. [ポリシーの評価論理（Policy evaluation logic）](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
1. [アクセス拒否のエラーメッセージのトラブルシューティング（Troubleshoot access denied error messages）](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_access-denied.html)
1. [AWS Identity and Access Management により、AWS のアクセス拒否のエラーを効率よく調べられるようになった（AWS Identity and Access Management now makes it more efficient to troubleshoot access denied errors in AWS）](https://aws.amazon.com/about-aws/whats-new/2021/11/aws-identity-access-management-efficient-troubleshoot-error/)
1. [アクセス拒否のエラーメッセージへのポリシーの ARN の追加（AWS What's New, 2026 年 1 月）](https://aws.amazon.com/about-aws/whats-new/2026/01/additional-policy-details-access-denied-error/)

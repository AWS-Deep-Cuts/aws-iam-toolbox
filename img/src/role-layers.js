// ハンズオン用ロールの設定の図。role-layers（事前準備の直後）と stage-1〜stage-4（各ステージの拒否の原因）を、同じ枠組みで描く。
// body の data-mode で描き分ける。枠組み（位置と大きさ）は 5 枚で同じで、強調と右の列の注記だけが変わる。
//   initial : setup.sh が作成した直後の設定。拒否の原因になる設定に、ステージの札を付ける。
//             右の列には、IAM コンソールのロールの画面で、その設定を確認する場所を書く
//   stage-N : そのステージで拒否の原因になる設定を差し色で強調し、修正の内容を右に書く。
//             ロールに無い設定（削除・デタッチしたもの、まだアタッチしていないもの）は点線で薄くする。
//             アタッチ・変更した設定はロールに残って評価に使われるため、通常の色のまま「〜済み」と書く
// 根拠:
//   - 行の中身は hands-on/setup.sh による。
//       行 1  put-role-policy    aws-deepcuts-inline-deny       Sid DenyReadCertificateInline  Deny iam:GetPolicy（Resource は修了証のポリシー）
//       行 2  attach-role-policy aws-deepcuts-managed-deny      Sid DenyReadCertificate        Deny iam:GetPolicy（Resource は修了証のポリシー）
//       行 3  create-policy      aws-deepcuts-read-certificate  Sid AllowReadCertificateForSecurityTeam
//             Allow iam:GetPolicy、Condition StringEquals aws:PrincipalTag/team = security。setup.sh ではアタッチしない
//       行 4  create-role --tags Key=team,Value=dev
//       行 5  create-role --permissions-boundary aws-deepcuts-boundary  Sid BoundaryAllowedActions
//             Allow iam:ListPolicies と sts:GetCallerIdentity。iam:GetPolicy を含まない
//   - ステージと修正は DESIGN-v3-iam.md の「ステージ」の表と、README の各ステージの「修正の手順」による。
//     IAM コンソールの「許可」タブで「削除」を選ぶと、インラインポリシーは削除され（DeleteRolePolicy）、
//     管理ポリシーはロールからデタッチされる（DetachRolePolicy）。管理ポリシーそのものは後片付けまで残る。
//   - コンソールの画面の名前（「許可」タブ・許可ポリシー・許可の境界・「タグ」タブ）は DESIGN-v3-iam.md の
//     「コンソールの操作で使う画面の名前」による
(() => {
  const MODE = document.body.dataset.mode || 'initial';
  const S = MODE === 'initial' ? 0 : Number(MODE.replace('stage-', ''));

  // ── 寸法 ─────────────────────────────────────────────
  const CARD_W = 470;          // ロールのカードの幅
  const BORDER = 3;            // カードの枠線
  const TAB_W = 318;           // 見出し（ロールの名前）の札の幅
  const TAB_H = 64;            // 見出しの札の高さ。矢印はこの中心の高さ
  const PAD = 8;               // カードの内側の余白
  const GAP = 8;               // 行と行の間
  const ROW_X = BORDER + PAD;
  const ROW_W = CARD_W - 2 * (BORDER + PAD);
  const RX = 506;              // 右の列（注記と修正）の左端
  const CERT_X = 590;          // 修了証のポリシーの左端
  const MID = TAB_H / 2;       // 矢印の高さ

  // ── 部品 ─────────────────────────────────────────────
  const code = (t, hot) => `<code${hot ? ' class="hot"' : ''}>${t}</code>`;
  const eff = (e, hot) => `<b class="eff ${e.toLowerCase()}${hot ? ' hot' : ''}">${e}</b>`;
  const stg = (n) => {
    const st = S === 0 ? '' : n === S ? ' now' : n < S ? ' done' : '';
    return `<span class="stg${st}">ステージ ${n}</span>`;
  };

  // 行。n はその行が拒否の原因になるステージ。where は IAM コンソールで確認する場所（initial だけに書く）
  const ROWS = [
    { id: 'r1', n: 1, h: 70, type: 'インラインポリシー', name: 'aws-deepcuts-inline-deny',
      lines: [`${eff('Deny', S === 1)} ${code('iam:GetPolicy')}`],
      absent: S >= 2, where: '「許可」タブ ・ 許可ポリシー', done: '削除済み' },
    { id: 'r2', n: 1, h: 70, type: '管理ポリシー', name: 'aws-deepcuts-managed-deny',
      lines: [`${eff('Deny', S === 1)} ${code('iam:GetPolicy')}`],
      absent: S >= 2, where: '「許可」タブ ・ 許可ポリシー', done: 'デタッチ済み' },
    { id: 'r3', n: 2, h: 92, type: '管理ポリシー', name: 'aws-deepcuts-read-certificate',
      lines: [`${eff('Allow')} ${code('iam:GetPolicy')}`,
              `条件：タグ ${code('team')} が ${code('security', S === 3)}`],
      absent: S <= 2, where: 'まだアタッチしていない', done: 'アタッチ済み' },
    { id: 'r4', n: 3, h: 70, type: 'タグ', name: '',
      lines: [`<span class="kv">${code('team')} <span class="op">=</span> ${code(S >= 4 ? 'security' : 'dev', S === 3)}</span>`],
      absent: false, where: '「タグ」タブ', done: '変更済み' },
    { id: 'r5', n: 4, h: 116, type: 'アクセス許可の境界', name: 'aws-deepcuts-boundary',
      lines: [`${eff('Allow')} ${code('iam:ListPolicies')} と`,
              `${code('sts:GetCallerIdentity')} だけ`,
              `<span class="${S === 4 ? 'hotline' : ''}">${code('iam:GetPolicy')} を含まない</span>`],
      absent: false, where: '「許可」タブ ・ 許可の境界', done: '' },
  ];
  // 右の列の注記
  const note = (r) => {
    if (S === 0) return r.where;
    if (r.n < S) return r.done;                     // 前のステージで解消した
    if (r.id === 'r3' && S < 2) return r.where;     // まだアタッチしていない
    return '';
  };

  // 各ステージの修正。管理者が IAM コンソールで行う操作（README の「修正の手順（IAM コンソール）」）
  const FIX = {
    1: { rows: ['r1', 'r2'], title: '2 つともロールから削除する', sub: '「許可」タブで 2 つを選択し、<br>「削除」を選ぶ' },
    2: { rows: ['r3'], title: 'ロールにアタッチする', sub: '「許可を追加」から<br>「ポリシーをアタッチ」を選ぶ' },
    3: { rows: ['r4'], title: 'タグ <span class="m">team</span> の値を<br><span class="m">security</span> に変更する', sub: '「タグ」タブで変更し、<br>CloudShell でロールに切り替え直す' },
    4: { rows: ['r5'], title: '<span class="m">iam:GetPolicy</span> を追加する', sub: 'ポリシーの「編集」で、<br><span class="m">Action</span> の配列に追加する' },
  };

  // 行の上端の y 座標
  const CARD_Y = TAB_H - BORDER;                // カードの上端。上の枠線は見出しの札に重ねる
  let y = CARD_Y + BORDER + PAD;
  const top = {};
  for (const r of ROWS) { top[r.id] = y; y += r.h + GAP; }
  const CARD_H = y - GAP + PAD + BORDER - CARD_Y;
  const LEGEND_Y = CARD_Y + CARD_H + 14;
  const FIG_H = LEGEND_Y + 30;

  const css = `
  #fig { width: 800px; height: ${FIG_H}px; }

  /* ロール：見出しの札（アイコンと名前）と、設定を並べたカード */
  .tab { position: absolute; left: 0; top: 0; width: ${TAB_W}px; height: ${TAB_H}px; background: var(--ink); color: #fff;
         display: flex; align-items: center; gap: 12px; padding: 0 12px; }
  .tab img { width: 42px; height: 42px; background: #fff; padding: 3px; display: block; flex: none; }
  .tab b { display: block; font-size: 18px; font-weight: 900; line-height: 1.3; }
  .tab code { display: block; font-family: var(--font-mono); font-weight: 800; font-size: 15px; color: #cfcabd; line-height: 1.35; }
  .rc { position: absolute; left: 0; top: ${CARD_Y}px; width: ${CARD_W}px; height: ${CARD_H}px; border: ${BORDER}px solid var(--ink); }

  /* 行：左に種類とステージの札、右に名前と中身 */
  .row { position: absolute; left: ${ROW_X}px; width: ${ROW_W}px; border: 2px solid var(--ink); background: #fff;
         display: flex; gap: 8px; padding: 7px 10px; }
  .row .k { width: 150px; flex: none; }
  .row .k > span:first-child { display: block; font-size: 16px; font-weight: 700; line-height: 1.4; }
  .row .k .stg { margin-top: 5px; }
  .row .v { flex: 1; min-width: 0; }
  .row .v > .n { display: block; font-family: var(--font-mono); font-weight: 800; font-size: 15px; line-height: 1.4; }
  .row .v > div { font-size: 16px; font-weight: 500; line-height: 1.5; white-space: nowrap; }
  .row .v > .n + div { margin-top: 3px; }
  .row code { font-family: var(--font-mono); font-weight: 800; font-size: 15px; }
  .row code.hot, .row .hotline, .row .hotline code { color: var(--hot); }
  .row .hotline { font-weight: 900; }
  .row .kv code, .row .kv .op { font-size: 17px; }

  /* Effect の札 */
  .eff { display: inline-block; font-family: var(--font-mono); font-weight: 800; font-size: 15px; line-height: 20px; padding: 0 6px; margin-right: 2px; border: 2px solid var(--ink); }
  .eff.deny { background: var(--ink); color: #fff; }
  .eff.allow { background: #fff; color: var(--ink); }
  .eff.hot { background: var(--hot); border-color: var(--hot); color: #fff; }

  /* ロールに無い設定：点線で薄く */
  .row.absent { border-style: dashed; border-color: var(--grey); background: transparent; color: var(--grey); }
  .row.absent .eff.deny { background: var(--grey); border-color: var(--grey); }
  .row.absent .eff.allow { background: transparent; border-color: var(--grey); color: var(--grey); }
  /* このステージの原因 */
  .row.now { border-color: var(--hot); box-shadow: 0 0 0 2px var(--hot); }
  .row.now.absent { border: 3px dashed var(--hot); box-shadow: none; padding: 6px 9px; color: var(--ink); }
  .row.now.absent .eff.allow { border-color: var(--ink); color: var(--ink); background: #fff; }

  /* ステージの札（how-to-read と同じ形） */
  .stg { display: inline-block; white-space: nowrap; font-size: 16px; font-weight: 700; line-height: 1.3; padding: 1px 8px;
         border: 2px solid var(--ink); background: #fff; color: var(--ink); }
  .stg.now { background: var(--hot); border-color: var(--hot); color: #fff; }
  .stg.done, .row.absent .stg:not(.now) { background: transparent; border-color: var(--grey); color: var(--grey); }

  /* 右の列：注記と、修正（差し色の枠） */
  .colh { position: absolute; left: ${RX}px; font-size: 16px; font-weight: 900; color: var(--grey); line-height: 22px; white-space: nowrap; }
  .note { position: absolute; left: ${RX}px; font-size: 16px; font-weight: 700; line-height: 22px; white-space: nowrap; }
  .note.where { color: var(--ink); font-weight: 500; }
  .note.done, .note.absent { color: var(--grey); }
  .fix { position: absolute; left: ${RX}px; width: ${800 - RX}px; border: 4px solid var(--hot); background: #fff; padding: 8px 12px 10px; }
  .fix > i { display: block; font-style: normal; font-size: 16px; font-weight: 900; color: var(--hot); line-height: 1.3; }
  .fix > b { display: block; font-size: 19px; font-weight: 900; line-height: 1.35; margin-top: 2px; }
  .fix > b .m { font-family: var(--font-mono); font-weight: 800; font-size: 17px; }
  .fix > span { display: block; font-size: 16px; font-weight: 500; line-height: 1.45; margin-top: 4px; }
  .fix > span .m { font-family: var(--font-mono); font-weight: 800; font-size: 15px; }
  .fix > b, .fix > span { white-space: nowrap; }

  /* 修了証のポリシー */
  .cert { position: absolute; left: ${CERT_X}px; top: 0; height: ${TAB_H}px; display: flex; align-items: center; gap: 10px; }
  .cert img { width: 48px; height: 48px; display: block; flex: none; }
  .cert b { display: block; font-size: 17px; font-weight: 900; line-height: 1.25; }
  .cert code { display: block; font-family: var(--font-mono); font-weight: 800; font-size: 15px; color: #4a4843; line-height: 1.25; }

  /* 矢印のラベル */
  .lbl.deny { color: var(--hot); font-weight: 900; line-height: 22px; }
  .lbl.deny code { font-family: var(--font-mono); font-weight: 800; font-size: 15px; }

  /* 凡例 */
  .legend { position: absolute; left: 0; top: ${LEGEND_Y}px; display: flex; align-items: center; gap: 10px; font-size: 16px; font-weight: 500; }
  `;
  document.head.insertAdjacentHTML('beforeend', `<style>${css}</style>`);

  // ── 描画 ─────────────────────────────────────────────
  let html = '';
  html += `<div class="rc"></div>`;
  html += `<div class="tab" id="tab" data-self="1">
      <img src="../icons/AWSIdentityAccessManagementRole.svg" alt="">
      <div><b>ハンズオン用ロール</b><code>aws-deepcuts-handson-role</code></div>
    </div>`;

  for (const r of ROWS) {
    const cls = ['row'];
    if (r.absent) cls.push('absent');
    if (r.n === S) cls.push('now');
    const name = r.name ? `<span class="n">${r.name}</span>` : '';
    html += `<div class="${cls.join(' ')}" id="${r.id}" data-self="1" style="top:${top[r.id]}px;height:${r.h}px">
      <div class="k"><span>${r.type}</span>${stg(r.n)}</div>
      <div class="v">${name}${r.lines.map((l) => `<div>${l}</div>`).join('')}</div>
    </div>`;
    const text = note(r);
    if (text) {
      const kind = S === 0 && r.id !== 'r3' ? 'where' : r.n < S ? 'done' : 'absent';
      html += `<div class="note ${kind}" style="top:${top[r.id] + r.h / 2 - 11}px">${text}</div>`;
    }
  }
  if (S === 0) html += `<div class="colh" style="top:${top.r1}px">IAM コンソールで確認する場所</div>`;

  html += `<div class="cert" id="cert" data-self="1">
      <img src="../icons/AWSIdentityAccessManagementPermissions.svg" alt="">
      <div><b>修了証のポリシー</b><code>aws-deepcuts-</code><code>certificate</code></div>
    </div>`;
  html += `<div class="lbl deny" id="lblAct"><code>iam:GetPolicy</code> は拒否される</div>`;

  const fix = FIX[S];
  if (fix) {
    // 1 行のときは、箱の上端を原因の行の上端にそろえる。2 行にまたがるときの位置は、文字の大きさが決まった後に決める
    html += `<div class="fix" id="fix" style="top:${top[fix.rows[0]]}px"><i>管理者が IAM コンソールで修正</i><b>${fix.title}</b><span>${fix.sub}</span></div>`;
  }

  html += `<div class="legend"><span class="stg">ステージ N</span><span>この設定が、拒否の原因になるステージ</span></div>`;

  const fig = document.getElementById('fig');
  fig.insertAdjacentHTML('beforeend', html);

  // 1px の点。wire() の端の 4px の余白を打ち消して、水平の線を引くために使う
  let np = 0;
  const pt = (x, yy) => {
    const id = `p${np++}`;
    fig.insertAdjacentHTML('beforeend', `<div id="${id}" data-self="1" style="position:absolute;left:${x}px;top:${yy - 0.5}px;width:1px;height:1px"></div>`);
    return `#${id}`;
  };
  const hline = (x1, x2, yy, o = {}) => wire(pt(x1 - 5, yy), pt(x2 + 4, yy), { from: 'r', to: 'l', noarrow: true, ...o });

  window.addEventListener('load', async () => {
    await document.fonts.ready;
    // 矢印のラベルを、矢印の上の中央に置く
    const ax = (TAB_W + CERT_X) / 2;
    const a = document.getElementById('lblAct');
    a.style.left = `${Math.round(ax - a.offsetWidth / 2)}px`; a.style.top = `${MID - 26}px`;
    // 修正が 2 行にまたがるときは、2 つの行の中心の中間に箱の中心を置く。
    // 2 本の線が箱の上下の端から 12px 以上内側に入るように、必要なら箱を高くする
    if (fix && fix.rows.length > 1) {
      const el = document.getElementById('fix');
      const cy = fix.rows.map((id) => top[id] + ROWS.find((q) => q.id === id).h / 2);
      const c0 = Math.min(...cy), c1 = Math.max(...cy);
      const h = Math.max(el.offsetHeight, c1 - c0 + 24);
      el.style.height = `${h}px`;
      el.style.top = `${Math.round((c0 + c1) / 2 - h / 2)}px`;
      el.style.display = 'flex'; el.style.flexDirection = 'column'; el.style.justifyContent = 'center';
    }
    // ロールとして、修了証のポリシーに iam:GetPolicy を呼び出す。どの図でも拒否される
    wire('#tab', '#cert', { from: 'r', to: 'l', hot: true });
    // 原因の行から、修正へ
    if (fix) for (const id of fix.rows) {
      const r = ROWS.find((q) => q.id === id);
      hline(ROW_X + ROW_W, RX, top[id] + r.h / 2, { hot: true });
    }
    document.body.dataset.ready = '1';
  });
})();

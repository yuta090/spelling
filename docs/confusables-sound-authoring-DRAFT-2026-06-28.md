# 【DRAFT】confusables_sound 辞書 量産ガイド（リスニングおとり・agy委譲用）— 2026-06-28

Status: **DRAFT v0**。リスニング設問（リスニング穴埋め／単語リスニング）実装前の準備。おぼえかた辞書と同じ承認運用。
関連: [exercise-formats-and-distractors-2026-06-28.md](exercise-formats-and-distractors-2026-06-28.md)（おとり設計・研究）/ [grammar-level-cefrj-2026-06-28.md](grammar-level-cefrj-2026-06-28.md)（学年の壁）

## 0. 目的
「音が紛らわしい語（minimal pair / sound-alike）」の辞書。**リスニングのおとり**を作る土台。
- 用途：①**単語リスニング**（音を聞いて正しいつづりを選ぶ）②**リスニング穴埋め**（設問中は無音・候補から選ぶ）。
- リスニングおとりは**自動生成できない**（音の近さは人の判断）＝**量産＋承認が要る本丸データ**。
- AI生成は **`approved=0`**、人が承認した行だけ同梱（おぼえかた辞書と同じ規律）。

## 1. データ形式（CSV）
`word, sounds_like, approved, source`
| 列 | 説明 | 例 |
|---|---|---|
| `word` | 小文字。wordbank に存在する語 | `right` |
| `sounds_like` | 音が近い語を `\|` 区切り（2〜4個） | `light\|write\|night` |
| `approved` | 1=出す / 0=未承認。**AIは必ず0** | `0` |
| `source` | `hand` / `ai` | `ai` |

## 2. いちばん大事な軸：日本人学習者の“聞き分け”
日本語話者が**特に混同する音**を最優先で集める（ここが学習効果の核心）：
- **L / R**：`right`↔`light`、`rice`↔`lice`、`glass`↔`grass`、`read`↔`lead`、`play`↔`pray`
- **B / V**：`boat`↔`vote`、`berry`↔`very`、`best`↔`vest`
- **TH / S・F**：`think`↔`sink`、`three`↔`tree`/`free`、`mouth`↔`mouse`
- **母音の長さ**：`ship`↔`sheep`、`hit`↔`heat`、`full`↔`fool`
- **語末子音 / 似た子音**：`cap`↔`cat`、`sea`↔`she`、`light`↔`right`↔`night`（韻）
> 研究的にも、**初級者ほど「音・つづりが近いおとり」が一番効く**（迷う＝学びになる）。意味の近さは上級向け（別辞書 `confusables_meaning`）。

## 3. 守るルール（破ったら却下）
1. `sounds_like` は **実在語（wordbank にある）**・**対象学年バンド内**・**`word` と別語**・**重複なし**。
2. **本当に音が近い**こと（minimal pair か強い類音）。遠い語・無関係語は入れない。**迷ったら入れない**。
3. **やさしい言葉**：子が知り得る常用語。学者語・難語・固有名詞・きわどい語は不可。
4. **2〜4個**。多すぎ・弱いおとりで薄めない。
5. **AI生成は `approved=0`**。音の近さは**人が最終判断**（機械は不確実）。
6. 反意語・正解の言い換えは不要（リスニングおとりの軸は“音”）。

## 4. 良い例 / 悪い例
**良い（日本人混同・実在・近い）**
```
right,light|write|night,0,ai
rice,lice|race|nice,0,ai
ship,sheep|chip|shop,0,ai
think,sink|thing|thank,0,ai
boat,vote|coat|goat,0,ai
```
**悪い（出すな）**
- `right,correct,0,ai` … 意味の近さ（音は遠い）。
- `ship,banana,0,ai` … 音が無関係。
- `rice,rices,0,ai` … 不自然/非実在の活用。
- `cat,Katherine,0,ai` … 固有名詞・難語。

## 5. ビルド検証（✅ 実装済 `confusables-build` ＋ Core `ConfusablesValidator`）
- 実行: `swift run confusables-build [--target-band N] [--write]`（原本CSV＋wordbank → 検証 → 同梱 `iPadPrototype/Resources/confusables_sound.build.csv`）。
- **ハード規則（違反は却下・書き出さない）**＝データだけで判定: 承認済み・`word`と別・重複なし・個数2〜4・正規化(小文字/トリム)・CSV安全(`,|`改行タブ禁止)・見出し語の二重登録なし。
- **wordbank 実在/band は警告のみ（自動削除しない）**（ユーザー決定 2026-06-28）。この wordbank の `gloss` には gray/math 等の実在語欠落があり、機械削除は良い手承認データを壊すため。警告を見て人が「辞書に足す」or「ペアを直す」を判断。
  - band は `level`（2,816語）にある語だけ判定可。未収録の易しい語は「band不明」警告にとどめる。
- `approved=1` のみ同梱。**音の近さは承認者（人）が最終判断**（機械は実在/band/重複/形式のみ）。

## 6. 使われ方（生成器との関係）
- **単語リスニング**：`word` の音を再生 → 候補＝`word`＋`sounds_like` から N 個（決定論シャッフル）。
- **リスニング穴埋め**：文の空所語が `word` のとき、`sounds_like` を**おとり候補プール**として `ClozeChoiceGenerator` に渡す（既存の純ロジックが正解＋おとりを組む）。文として自然に出すため、生成器側で**品詞・長さ**もゆるく見る（リスニングは音優先）。
- これにより、自動生成系（語形変化・同band）と**役割分担**：confusables_sound は“音”専門。

## 7. agy 委譲プロンプト（下書き・コピペ用）
> あなたは日本の小中学生向け英語ゲームの**リスニング教材編集者**です。これは採点テストでなく、
> 「間違えてOK・もう一回」と思える**やさしいゲーム**。日本語話者が**聞き間違えやすい音**を集めます。
> 次のルールで CSV 行を作ってください（`word,sounds_like,approved,source`）。
>
> 【最優先】日本人が混同しやすい音を狙う：**L/R・B/V・TH/S・母音の長さ・語末子音**
> （例：right↔light、rice↔lice、ship↔sheep、think↔sink、boat↔vote）。
> 【ルール】
> - `sounds_like` は `|` 区切りで **2〜4個**。**実在する常用語**で、**本当に音が近い**もの限定。
> - 対象学年バンド {band} 以内のやさしい語のみ。固有名詞・難語・きわどい語・非実在活用は禁止。
> - 意味の近さ（synonym）や無関係語は入れない（軸は“音”）。**迷ったら入れない（空でよい）**。
> - `approved` は必ず `0`、`source` は必ず `ai`。
> - 対象語リスト：[ここに wordbank 抽出の対象語を貼る]
>
> ※ この後、人が「本当に音が近いか」を1語ずつ確認して承認します。だから**自信のある近さ**だけ。
> 最後に「対象語数・生成行数・狙った音カテゴリ（L/R等）の内訳」を要約報告。

## 8. 確定条件（このDRAFTを確定版にする）
1. リスニング設問の実装方針確定（単語リスニング/穴埋めのどちらを先に）。
2. **ビルド/検証スクリプト**（§5）＋同梱形式。wordbank 抽出の対象語リスト作成。
3. 小バッチ（30〜50語）で agy 試走 → 人が音の近さを承認 → 運用化。

> 姉妹辞書 `confusables_meaning`（意味が近いおとり・上級用）は**別途・慎重に**（“第2の正解”化を避ける）。本DRAFTは音(_sound)専用。

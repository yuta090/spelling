# 【DRAFT】例文テンプレ量産ガイド（agy 委譲用）— 2026-06-28

Status: **DRAFT v0**。コア（`feat/cast-sentences-20260628-c4s7` の `PersonalizedSentences.swift`）main マージ後＋ビルド/ローダ確定後に確定版へ。
関連: [personalized-sentences-spec-2026-06-28.md](personalized-sentences-spec-2026-06-28.md) / [exercise-formats-and-distractors-2026-06-28.md](exercise-formats-and-distractors-2026-06-28.md) / [grammar-level-cefrj-2026-06-28.md](grammar-level-cefrj-2026-06-28.md)

## 0. 目的
例文・クイズ文を **`PersonSentenceTemplate`（役スロット付きテンプレ）** として量産する。
- **全コンテンツはテンプレ**：名前ありも、プレーン文も同じ形（プレーン＝スロット無し＝`fallback` だけ）。
- AI生成は **`approved=0`**、人が承認した行だけ同梱（おぼえかた辞書と同じ規律）。
- 出力はそのまま `SentencePersonalizer.resolve` が食えるように**コアの Codable 形に一致**させる（ビルドで id 付与・検証）。

## 1. authoring 形式（1テンプレ＝1 JSON オブジェクト）
コアの Codable に一致。**`fallback` の `id` は書かない（ビルドが付与）／`approved`・`source` は authoring 専用（ビルドが剥がす）**。

```json
{
  "id": "play-invite-tomorrow",
  "category": "play",
  "grammar": "canModal",
  "gradeBand": 1,
  "contentLemmas": ["play", "tomorrow"],
  "slots": [ {"key": "f", "role": "friend"} ],
  "enTokens": [
    {"kind": "person", "slot": "f", "form": "vocativeName", "suffix": ","},
    {"kind": "literal", "text": "let's"},
    {"kind": "literal", "text": "play"},
    {"kind": "literal", "text": "tomorrow"}
  ],
  "jaParts": [
    {"kind": "person", "slot": "f", "suffix": "、"},
    {"kind": "literal", "text": "あした あそぼう"}
  ],
  "fallback": {
    "en": "Let's play tomorrow",
    "ja": "あした あそぼう",
    "tokens": ["Let's", "play", "tomorrow"],
    "gradeBand": 1,
    "contentLemmas": ["play", "tomorrow"],
    "grammar": "canModal"
  },
  "approved": 0,
  "source": "ai"
}
```

### 列挙の許可値（コアと一致・厳密）
- `category`：`school` / `play` / `greeting` / `home` / `daily` / `other`
- `role`：`child` / `friend`（`slots[].role`）
- `requiredGender`（任意）：`boy` / `girl`（省略＝無制約）
- `form`（`person` トークン）：`name` / `namePossessive` / `subjectPronoun` / `objectPronoun` / `possessiveDeterminer` / `vocativeName`
- `grammar`：`GrammarPoint` の raw（`beVerb`/`presentSimple`/`pastSimple`/`canModal`/`comparativeEr` …）。無ければ省略。
- `gradeBand`：1〜5（NGSL・語彙の壁）

## 2. 守るルール（破ったら却下）
**A. プロダクト共通（解説・全文に効く）**
1. **ゲームのやさしいヒント**：短く・前向き・子向け。級/CEFR/点数は出さない。
2. **学年の壁**：`gradeBand` 内の語彙・`grammar` の段階内。難語を持ち込まない。
3. **迷ったら作らない**：不自然・自信が無い文は出さない。
4. **AI生成は `approved=0`**。

**B. パーソナライズ固有（一致崩れを原理的に防ぐ）**
5. **活用・代名詞・助詞は“作成時に確定”**：動詞リテラルは結果の形に合わせて**最初から正しく**書く。
   - 友達名・代名詞は**1人＝3人称単数**：`{f:name} likes apples`（`like` でなく `likes`）。
6. **友達は必ず性別あり**（登録で必須）＝代名詞は **he/she/his/her（3単）** に解決。**`they` 前提のテンプレを作らない**。
7. **本人（`role:child`）は呼びかけ専用**：`vocativeName` のみ。本人を**主語・所有格・目的格にしない**（`Yuta likes…` 禁止）。
8. **大文字化**：`subjectPronoun`/`objectPronoun`/`possessiveDeterminer` は**小文字**を返す → **文頭に置かない**（文頭は `literal` か `name`/`vocativeName`＝大文字始まりのローマ字）。最初の可視トークンは大文字始まり。
9. **名前は語彙にしない**：`contentLemmas` に名前を入れない。`fallback.tokens` にも“役名”を出さない（fallback は正常な代名詞文）。
10. **トークン整合**：`enTokens` を描画して `tokens` になり、`tokens.joined(" ")==en` になること。`fallback.tokens.joined(" ")==fallback.en`。
11. **スロット参照の整合**：`enTokens`/`jaParts` が参照する `slot` は必ず `slots[]` に在る。
12. **fallback は“正常な既定文”**：Cast 不足/機能オフでそのまま出る。名前なしで自然・文法/語彙が本文と同等。
13. **決定論安全**：`id` は人が読めるユニーク文字列（重複禁止）。

## 3. 良い例 / 悪い例
**良い（友達 主語・3単一致）**
```json
{"id":"friend-likes-apples","category":"daily","grammar":"presentSimple","gradeBand":1,
 "contentLemmas":["like","apple"],"slots":[{"key":"f","role":"friend"}],
 "enTokens":[{"kind":"person","slot":"f","form":"name"},{"kind":"literal","text":"likes"},{"kind":"literal","text":"apples"}],
 "jaParts":[{"kind":"person","slot":"f","suffix":"は"},{"kind":"literal","text":" りんごが すき"}],
 "fallback":{"en":"She likes apples","ja":"かのじょは りんごが すき","tokens":["She","likes","apples"],"gradeBand":1,"contentLemmas":["like","apple"],"grammar":"presentSimple"},
 "approved":0,"source":"ai"}
```
**良い（本人 呼びかけ）**：`{"kind":"person","slot":"me","form":"vocativeName","suffix":","}`,`Look`,`,`... → 「Yuta, look!」（`slots:[{"key":"me","role":"child"}]`）

**悪い（出すな）**
- `{f:name} like apples` … 3単一致崩れ（`likes` にする）。
- 本人を主語：`{me:name} likes…` … 一致/所有格が崩れる（本人は呼びかけのみ）。
- 文頭に `subjectPronoun`：`{f:subjectPronoun} runs` を文頭 … 小文字 "he runs"。文頭は `name`/`literal`。
- `they` 前提：`{f:subjectPronoun} are happy` … 友達は3単（he/she）。

## 4. ビルド検証チェックリスト（companion スクリプト＝別途・未実装）
- 列挙値の妥当性／`slot` 参照整合／`tokens.joined==en`（本文・fallback）／`contentLemmas` に名前なし／`gradeBand`1–5／`grammar` 値妥当／文頭大文字／代名詞が文頭に無い／`id` 重複なし。
- 通過した `approved=1` 行だけ `sentence_templates`（同梱）へ。`fallback.id` はビルドで決定論付与。

## 5. agy 委譲プロンプト（下書き・コピペ用）
> あなたは日本の小中学生向け英語ゲームの**例文テンプレ編集者**です。これは採点テストでなく、
> 「間違えてOK・もう一回」と思える**やさしいゲーム**の中の文です。次のルールで、役スロット付きの
> 文テンプレを **1テンプレ＝1 JSON** で作ってください（配列で複数返す）。
>
> 【最優先】上の §1 形式・§2 ルールに**厳密に従う**。破った行は却下。特に：
> - 動詞・代名詞・助詞は**作成時に正しく確定**（友達名＝3人称単数：`likes`）。
> - **友達は he/she/his/her（3単）**。`they` 前提にしない。**本人は呼びかけ(`vocativeName`)専用**。
> - 小文字代名詞は**文頭に置かない**。最初の可視トークンは大文字始まり。
> - **名前を `contentLemmas` に入れない**。`fallback` は名前なしの正常文。
> - 出力は §1 の JSON 形に一致（`approved:0`,`source:"ai"`）。`fallback.id` は書かない。
>
> 【お題】カテゴリ「{category}」で、対象学年バンド {gradeBand} 以内、文法は {grammar 候補} を使い、
> **子どもが実際に使う自然な会話**（誘う・あいさつ・学校・あそび 等）を **{N}本**。
> 友達スロットは `f`（必要なら `friendA`/`friendB`＋`child` 呼びかけ）。3人会話は別人2スロット＋本人呼びかけ。
>
> 既出 `id` と重複しないこと。自信が無い・不自然なら出さない（空でよい）。
> 最後に「カテゴリ別の件数・合計・自己チェック（一致/大文字/名前非語彙）」を要約報告。

## 6. 残りの段取り（このDRAFTを確定版にする条件）
1. コア（`PersonalizedSentences.swift`）main マージ。
2. **ビルド/ローダ確定**：`sentence_templates` 同梱形式＋検証スクリプト（§4）。`fallback.id` 付与方式。
3. 上記に合わせて §1 形式・§5 プロンプトを**確定**（必要なら CSV ではなく JSONL 等を決める）。
4. 小バッチ（1カテゴリ20〜30本）で agy 試走 → 私レビュー → 承認運用を回す。

# オーサリング書式：例文パーソナライズ テンプレ（AI/人が書く用）

Status: v1（2026-06-28）。ローダ実装＝`Sources/SpellingSyncCore/PersonTemplateAuthoring.swift`。
親仕様: [personalized-sentences-spec-2026-06-28.md](personalized-sentences-spec-2026-06-28.md)。
**このファイルは「テンプレを量産する人/AIが見る書式定義」**。生成物（JSON配列）はこの書式に従う。

## これは何
役スロット付きの例文テンプレを、**簡潔な JSON** で書くための書式。
ここで書いた1件が、子の登録した友達/本人の名前を入れて1つの英文（並べ替え/答え合わせに出る文）になる。
UUID や冗長なタグは書かない。ローダ(`PersonTemplateAuthoring.load`)が決定論的に内部型へ変換する。

## 1レコードの形（JSON）
```json
{
  "id": "friend-likes-apples",          // 一意。kebab-case。重複NG
  "category": "daily",                   // school|play|greeting|home|daily|other
  "grammar": "presentSimple",            // 文法タグ（任意）。無ければ省略 or null
  "gradeBand": 1,                        // 語彙の壁（1..5）。内容語の最大NGSLバンド
  "contentLemmas": ["like","apple"],     // 採点/語彙判定に使う内容語。★名前は入れない
  "slots": [
    {"key":"f","role":"friend","gender":"girl"}  // gender は friend のみ・省略=無制約
  ],
  "en": ["{f:name}","likes","apples"],   // 英語トークン列（並べ替えの正解順）
  "ja": "{f}は りんごが すき",            // 日本語（名前は {slot} で差し込み）
  "fallbackEn": ["She","likes","apples"],// Cast不足時に出す“正常な”既定文（名前なし）
  "fallbackJa": "かのじょは りんごが すき"
}
```
ファイルは **この形のレコードの配列** `[ {...}, {...} ]`。

## en（英語トークン）の書き方
- 配列の各要素が**タイル1個**（並べ替えの1ピース）。
- リテラルはそのまま： `"likes"`, `"apples"`。
- 人物参照は `"{slot:form}"`。末尾に句読点を付けるとそのトークンに含まれる： `"{me:vocative},"` → `Yuta,`。
- **form 一覧**：
  | form | 出力（例: 女の子Yuki / 男の子Ken） | 用途 |
  |---|---|---|
  | `name` | Yuki / Ken | 名前（主語・目的語の固有名詞） |
  | `possessive` | Yuki's / Ken's | 所有（名前+'s） |
  | `subject` | she / he | 主語代名詞（※小文字。文頭なら name を使う） |
  | `object` | her / him | 目的格代名詞 |
  | `posdet` | her / his | 所有限定詞（her bag） |
  | `vocative` | Yuki / Ken | 呼びかけ（本人専用。"," は末尾に付ける） |

## ja（日本語）の書き方
- 1つの文字列。名前を出す所だけ `{slot}` を置く（例 `"{f}は ともだち"`）。
- 助詞（は/が/と…）は**そのままリテラル**で書く（活用問題が無いので変形不要）。

## slots
- `key`：en/ja の `{key…}` と一致させる。`f`/`friendA`/`me` 等。
- `role`：`friend` か `child`。
- `gender`：`boy`/`girl`。**friend で代名詞(he/she 等)を使う時は必須**。省略すると無制約。

## 絶対ルール（破ったらローダが弾く＝ビルド失敗）
1. **本人(child)スロットは英語では `vocative` だけ**。`{me:name}`/`{me:subject}` 等は禁止
   （"I" 主語に名前を入れると `Yuta like…` と一致が崩れるため）。日本語の `{me}` はOK。
2. **en/ja で参照した slot は必ず slots に宣言**。宣言したのに未使用もNG。
3. **form 名は上表のものだけ**。
4. **id は一意**。
5. **en / fallbackEn は空にしない**。

## 守るべき内容ルール（プロダクト規約・人手レビューで担保）
- **名前を語彙にしない**：`contentLemmas` に人名を入れない。出題語(綴り練習)に名前は使わない。
- **活用・代名詞は最初から正しく**書く（`likes`/`his`/`her`）。ローダは活用変形しない。
- 子ども向けトーン：短く・やさしく・前向き。対象学年(gradeBand)より難しい語を入れない。
- **fallback は名前なしで文として正しい**こと（Cast未登録でもそのまま出せる）。
- カテゴリ例：`school`=学校の会話、`play`=あそび/さそい（「明日あそぼう」）、`greeting`=あいさつ。
- **承認**：AI生成は人手レビュー前提（approved 相当）。怪しい一致/不自然はレビューで落とす。

## 変換できる例（before → after は resolver が実生成）
| en（テンプレ） | 友達Yuki(girl)/本人Yuta で |
|---|---|
| `["{f:name}","likes","apples"]` | Yuki likes apples |
| `["This","is","{f:posdet}","bag"]` | This is her bag |
| `["{me:vocative},","let's","play"]` | Yuta, let's play |
| `["{me:vocative},","let's","play","with","{f:name}"]` | Yuta, let's play with Yuki（3人・別人割当） |

## 動作確認（生成後）
`PersonTemplateAuthoring.load(jsonArray:)` が**例外なく全件**通れば書式OK。
意味/トーンの妥当性は人手レビュー（resolver で数パターンの Cast に解決して目視）。

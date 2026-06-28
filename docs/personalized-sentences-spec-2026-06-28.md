# 仕様書：例文パーソナライズ（キャスト＋役スロット）

Status: **v1・他AI共有版**（2026-06-28）。codex Architect レビュー反映。
関連: [learning-loop-design-2026-06-28.md](learning-loop-design-2026-06-28.md) / [answer-explanation-spec-2026-06-28.md](answer-explanation-spec-2026-06-28.md) / [sentence-builder-design-2026-06-27.md](sentence-builder-design-2026-06-27.md)。
読む人: この機能を実装/レビューする別エージェント。**この1枚で自己完結**するよう書く。

---

## 0. 目的（なぜやるか）
例文・クイズ文を、その子の世界（本人・友達）に合わせて出す。
ゲームで仲間に友達の名前を付けると楽しいのと同じで、**自分ごと化**は記憶と意欲に効く。
- 友達の名前が文に登場する：「**Yuki** is my friend」「**Ken** can run fast」
- 本人の名前は**呼びかけ文**で登場：「**Yuta**, this is for you.」「Look, **Yuta**!」
- 「明日一緒に遊ばない？」のような**子どもが実際に使う会話**を増やし、「学校での会話」などの**カテゴリ**で問題セットを作れる。

出てくる文は最終的に既存の `SentenceItem` になるので、**並べ替えクイズ／答え合わせカード（AnswerExplanation）は一切変更不要**。

## 0.1 大前提（プロダクト規約・最優先）
- **2人のユーザー軸を守る**：友達を**登録するのは親**（管理・情報密度OK・親ゲートの奥）。**名前が文に出る楽しさは子**（doer）。子に専門用語・級・点数は出さない。
- **子どもが見るトーン**：短く・やさしく・前向き。
- **名前は語彙ではない**：友達/本人の名前を**つづり練習の出題語にしない**。例文・クイズ文の“中”にだけ出す。「しらない ことば」復習チップにも名前を出さない。
- **決定論**：選択・並びに `Date()`/乱数/`hashValue` を使わない。seed から再現可能に（`SpellingSyncCore` の方針）。
- **プライバシー**：未成年の実名。**v1 はローカル保存のみ**（Supabase 同期しない・解析に送らない・親ゲートの奥で編集）。

---

## 1. 全体構造（データの流れ）
```
親が登録          静的同梱（承認済み）           純粋関数（決定論）        既存UIそのまま
┌─────────┐      ┌──────────────────────┐    ┌────────────────┐   ┌──────────────┐
│  Cast   │ ───▶ │ PersonSentenceTemplate │──▶│SentencePersonalizer│─▶│ SentenceItem │─▶ 並べ替え/カード
│(ローカル)│      │ (wordbank.sqlite 同梱) │    │ .resolve(t,cast,seed)│  └──────────────┘
└─────────┘      └──────────────────────┘    └────────────────┘
```
- **Cast**：その世帯の登場人物（本人＋友達複数）。親がローカル登録。
- **PersonSentenceTemplate**：役スロット付きの“文のもと”。**英語トークン・日本語・スロット要件・正常なフォールバック文**を一緒に持つ（＝動詞や代名詞は最初から正しく書いておく＝後から活用変形しない）。
- **SentencePersonalizer.resolve**：テンプレ＋Cast＋seed → 解決済み `SentenceItem`。純粋・決定論。
- 以降は既存の `WordOrderingGenerator` / `SentenceFeedback` がそのまま食う。

### 設計の肝（codex Architect 結論）
> **生の文を後から書き換えない。** スロット付きで“最初から正しく書かれた”テンプレだけをレンダリングする。動詞の活用（like→likes）・代名詞（he/she）・日本語助詞は**作成時に確定**させ、実行時は名前を流し込むだけ。これで主語動詞一致・性別の崩れが原理的に起きない。

---

## 2. 型スケッチ（`SpellingSyncCore`・新規）
```swift
// MARK: Cast（その子の登場人物。親が登録。ローカル保存）
public struct Cast: Equatable, Codable, Sendable {
    public var people: [CastPerson]
}
public struct CastPerson: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var role: CastRole          // .child は1人、.friend は複数OK
    public var gender: PersonGender     // 友達は必須(he/she)。本人は不要→.unspecified
    public var displayNameJa: String    // "ゆうた"（親の一覧表示用）
    public var romaji: String           // "Yuta"（英文に出す綴り。英1トークン）
    public var avatarCharacterID: String? // 既存キャラ図鑑(HomeRewardCharacter)の id。nil=既定
    public var isActive: Bool           // 一時的に登場させない切替
}
public enum CastRole: String, Codable, Sendable { case child, friend }
public enum PersonGender: String, Codable, Sendable { case boy, girl, unspecified }
```
**性別（決定）**：友達のみ性別必須。**本人(.child)は性別不要**＝呼びかけ専用で代名詞一致が起きない（`.unspecified` で登録／登録UIでも聞かない）。将来「友達が本人を3人称で噂する」文を入れる時だけ本人性別が要る（v1スコープ外・フィールドは温存）。
**アバター（決定）**：cast のアバターは**アプリ既存のキャラ図鑑 `HomeRewardCharacter`（"bear"/"cat"…、`scripts/characters.csv` 生成・unlocked管理あり）から選ぶ**。純粋層は `avatarCharacterID`（不透明 id）だけ持ち、アプリ層が既存のキャラピッカー＋`RewardCharacterAvatar` で描画。新しい見た目を増やさず、子が普段使う自分のキャラを再利用する。
```swift

// MARK: 文のもと（スロット付き・承認済みを同梱）
public struct PersonSentenceTemplate: Equatable, Codable, Sendable {
    public var id: String
    public var category: SentenceCategory      // 学校/あそび/あいさつ… 親の問題セット用
    public var fallback: SentenceItem          // Cast不足時に出す“正常な”既定文
    public var enTokens: [EnglishTokenTemplate]
    public var jaParts: [JapaneseTextPart]
    public var slots: [PersonSlotSpec]
    // 解決後 SentenceItem へコピー
    public var gradeBand: Int
    public var contentLemmas: [String]         // 名前は絶対に含めない
    public var grammar: GrammarPoint?
}
public struct PersonSlotSpec: Equatable, Codable, Sendable {
    public var key: String                     // "friendA" / "friendB" / "child"
    public var role: CastRole
    public var requiredGender: PersonGender?    // 友達スロットの性別要件
}
public enum PersonReferenceForm: String, Codable, Sendable {
    case name              // Yuki
    case namePossessive    // Yuki's
    case subjectPronoun    // he/she
    case objectPronoun     // him/her
    case possessiveDeterminer // his/her
    case vocativeName      // 呼びかけ（本人専用想定）
}
public enum EnglishTokenTemplate: Equatable, Codable, Sendable {
    case literal(String)
    case person(slot: String, form: PersonReferenceForm, suffix: String = "") // suffix=","等
}
public enum JapaneseTextPart: Equatable, Codable, Sendable {
    case literal(String)
    case person(slot: String, suffix: String = "")
}
public enum SentenceCategory: String, Codable, Sendable {
    case school        // 学校での会話
    case play          // あそび・さそい（「明日あそ ぼう？」）
    case greeting      // あいさつ
    case home, daily   // 家・日常
    // …必要に応じて追加
}
```

## 3. 解決関数（純粋・決定論）
```swift
public enum SentencePersonalizer {
    /// テンプレ＋Cast＋seed → 解決済み SentenceItem。
    public static func resolve(_ t: PersonSentenceTemplate, cast: Cast, seed: UInt64) -> SentenceItem
}
```
ルール：
1. **候補抽出**：各スロットを role＋requiredGender で絞り、`isActive` のみ。並びは **id か親の登録順で安定ソート**。
2. **選択（疑似ランダム＝決定論）**：`stableHash(t.id, slot.key, seed) % count` で1人選ぶ。seed が同じなら毎回同じ＝再現可能。
3. **複数スロットは“別人”になるよう**選ぶ（友達A＝友達B を避ける。3人会話に必須）。同一人物しかいなければフォールバック。
4. **不足時フォールバック**：必要スロットを埋められなければ `t.fallback`（最初から正常な文）をそのまま返す。→ **未登録でも今日と同じ挙動**。
5. **レンダリング**：`enTokens`→`tokens`/`en`、`jaParts`→`ja`、`gradeBand/contentLemmas/grammar` をコピー、**決定論的な item.id** を付与。
6. **日本語も名前を入れる**：JP は活用問題が無いので `person(slot)` をそのまま名前差し込み（例：「{friendA}は ともだち」）。

### 本人名の扱い（重要・ユーザー案＝採用）
- 本人（`.child`）は **`vocativeName`（呼びかけ）専用**にする：`["{child.vocativeName},","this","is","for","you"]` → 「Yuta, this is for you.」
- **やってはいけない（v1）**：本人名を主語"I"の位置に入れる（`Yuta like…` 一致崩れ）／`I see Yuta`／`Yuta's bag…`。
- 理由：本人を**節の外（呼びかけ）**に置けば一致・所有格の問題が起きない。codex も「v1の正しい制約」と評価。

## 4. カテゴリと“子ども会話”の拡充（ユーザー案）
- `category` で **「学校での会話」「あそびのさそい」** 等の**問題セット**を親が作れる（レベル生成ツールと同じ親側の道具。子には出さない）。
- 子どもが実際に使う自然文を増やす：例「Let's play tomorrow.」「Can I join?」「See you tomorrow.」。
  - これらも**スロット付きテンプレ**にすれば、友達への呼びかけ／友達からの誘いとして名前が乗る。
- 量産は **AI生成の構造化データ＋ `approved=0` 人手ゲート**（他機能と同じ運用）。生の文章をAIに書かせるのではなく、トークン列＋スロット＋日本語＋フォールバックを構造で出させ、人が承認した行だけ同梱。

## 5. 複数友達・3人会話（ユーザー案）
- 友達は**複数登録**前提（`Cast.people` 配列）。1文に出るのは seed 選択で**毎回ちがう顔**になる＝飽きにくい。
- **3人会話**：スロットを `friendA`/`friendB`（＋`child` 呼びかけ）と複数置き、§3-3 の**別人選択**で成立。
  - v1 は**1文＝1問**を維持（並べ替えは1文）。会話は「1文ずつのテンプレ列」で表現し、**同じ会話内は Cast 選択を固定**（seed を共有）して名前の一貫性を保つ、を v1.1 拡張として明記（v1 で過剰実装しない）。

## 6. 保存・登録・統合
- **保存**：`Cast` は **ローカル JSON（`AppPersistenceStore`）**。Supabase 同期は v1 では**しない**（未成年実名のため）。
- **登録UI**：親ゲートの奥。入力＝**名前(かな)＋ローマ字＋役＋アバター**、友達のみ**性別**（本人は性別を聞かない）。アバターは既存キャラ図鑑 `HomeRewardCharacter` のピッカー（unlocked のみ）を再利用し `avatarCharacterID` を保存。既存の見た目言語（角丸カード・一覧・`RewardCharacterAvatar`）を再利用。子の画面・ホームには出さない。
- **テンプレ同梱**：`wordbank.sqlite` に**静的 `sentence_templates` テーブル**を追加（ソースは JSON/CSV→ビルド時生成）。アプリは `approved=1` のみロード。
- **既存統合**：`resolve` 済み `SentenceItem` を渡すだけ。`WordOrderingGenerator`/`WordOrderingGrader`/`SentenceFeedback`/`AnswerExplanationCard` は**無改修**。
- **語彙系から名前を排除**：`contentLemmas` に名前を入れない。「しらない ことば」チップは `item.tokens` ではなく **`contentLemmas`（=語彙トークン）由来**に切替（パーソナライズ有効時）。

## 7. フォールバック（縮退）
- Cast 空 / 機能オフ / 必要スロット不足 → `template.fallback`（正常な既定文）。**＝今日と同じ体験**。
- ローマ字未入力の人は候補から除外（英文に出せないため）。

## 8. テスト（TDD・`swift test` 緑・決定論）
1. friend 主語：`{girlFriend.name} likes apples` → "Yuki likes apples"（一致は作成済みなので壊れない）。
2. 性別：`he/him/his` は boy、`she/her/her` は girl のみ。要求性別が無ければフォールバック。
3. 本人呼びかけ：`{child.vocativeName}, look!` → "Yuta, look!"。本人が未登録ならフォールバック。
4. 複数スロット別人：friendA≠friendB。1人しかいなければフォールバック。
5. 決定論：同 seed→同結果、別 seed→分布が変わる。`Date()`/乱数/`hashValue` 不使用。
6. 日本語：`jaParts` に名前が入る。助詞が壊れない（作成時確定）。
7. 名前は `contentLemmas` に出ない（語彙汚染しない）。

## 9. 工数・リスク（codex）
- **工数：Medium（1〜2日）**＝コア型＋resolver＋テスト＋ローカル保存＋親登録UI＋ローダ＋小さな承認済みテンプレ集。
  - Tanaka 数千文を一括スロット化しようとすると Large。**v1 はやらない**（小さく作って増やす）。
- **リスク**
  - 一致崩れ：生文を変形しない／表層形を作成時確定で回避。
  - 名前が綴り練習に侵入：`contentLemmas`除外＋チップを語彙限定で回避。
  - 代名詞の性別ズレ：requiredGender＋he/him/his・she/her/her のテスト。
  - 未成年プライバシー：ローカルのみ・親ゲート・無解析・v1非同期。
  - 文の品質：AI生成は `approved=0`→人手承認→同梱。

## 10. スコープ外（将来）
3人以上の会話の同一Cast固定（v1.1）、Supabase同期（同意設計が要る）、ニックネーム/ペット、活用エンジン（不要＝テンプレで足りる）、子による友達追加（あくまで親管理）。

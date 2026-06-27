# 文法レベルの基準：CEFR-J × 学習指導要領（調査と対応表）— 2026-06-28

Status: 採用決定（CEFR-J 基準・親には学年表示）。実装は `SpellingSyncCore/GrammarLevel.swift`。
関連: [sentence-builder-design-2026-06-27.md](sentence-builder-design-2026-06-27.md) / [eiken-level-mapping.md](eiken-level-mapping.md)

## 1. 調査結論：日本 vs 海外の差
- **ネイティブの学校（米英豪）は文法を段階学習しない**。母語として自然習得するため、学校（Common Core ELA 等）は読み書き・リテラシー中心で「be動詞→過去形→現在完了」のような**学年配当が存在しない**。→ 参照にならない。
- **“外国語として学ぶ”世界（ESL/EFL）は CEFR（A1→C2）で段階化**。子ども向けは Cambridge **Pre-A1 Starters / A1 Movers / A2 Flyers**。これは使える文法ラダー。
- **日本の学習指導要領（2020/2021改訂）**は文法が前倒し：小学校で英語教科化、**中1で全時制（現在・過去・未来）を集約**、中2で受動態・現在完了、中3に現在完了進行・原形不定詞・仮定法。

→ 使える“学習要項”は実質 **CEFR(-J) と 学習指導要領** の2つ。両者は **英検＝CEFR 換算（公式）** で地続き。本アプリは既に英検級＋NGSL を使うため整合する。

## 2. 採用方針
- **内部の文法ラダー基準＝CEFR-J**（A1.1〜）。無料・**商用利用可**（出典明記のみ）の grammar profile があり、文法項目に CEFR-J レベルが付く＝**タグ付けの正解表**になる。日本人学習者向け設計。
- **親には CEFR を見せず「学年」で表示**（学習指導要領の言葉）。

## 3. 対応表（アプリ段階 × CEFR-J × 学年 × 英検）
| アプリ段階 (`GrammarStage`) | CEFR-J | 学年（指導要領の目安） | 英検 | 代表的な文法（`GrammarPoint`） |
|---|---|---|---|---|
| `intro1` | A1.1 | 小学校 | 5級手前 | be動詞 / This・That is / a・an・the / can / 代名詞 / 複数形 / 現在形 |
| `intro2` | A1.2 | 小6〜中1 | 5級 | 現在進行形 / 否定文 / Yes-No疑問 / be動詞の過去 / 頻度の副詞 |
| `basic1` | A1.3 | 中1 | 4級 | 一般動詞の過去(-ed) / 比較級(-er) / 命令文 / 疑問詞(why/where/when/how) |
| `basic2` | A2.1 | 中2 | 3級 | will・be going to / should / 受動態 / 不定詞 / 間接話法 |
| `applied` | A2.2 | 中2〜中3 | 準2級手前 | have to・need to / 動名詞 / 現在完了 |

> ⚠️ 受動態・現在完了の厳密な配置は CEFR-J と指導要領で少しズレる（指導要領は中2寄り）。本表は**叩き台**。CEFR-J 生データ＋指導要領で**運用しながら微調整**する。
> 解説文（`explanationJa`）も**暫定**。子向けのトンマナで後日磨く。
> **未来形（will / be going to）の扱い**：学習指導要領は中1で全時制（未来含む）を扱うが、**本表は CEFR-J 基準を採用**して `basic2`(A2.1/中2相当) に置く（コードもこの表に従う）。指導要領寄りに前倒ししたければ `willGoingTo` を `basic1` 等へ移すだけでよく、`testExhaustiveStageMappingMatchesTable` が表↔コードのズレを検知する。
> **fail-open の注意**：`grammar == nil` の文は文法の壁を**通過する**（暫定文・機能語のみ等のため）。本番の文バンクは**全文にタグ付け／意図的な exempt のみ nil** を前処理で保証し、未タグの上級文がすり抜けないようにする。

## 4. アプリへの落とし込み
- 文に **`GrammarPoint`（文法タグ）** を1つ付与 → `stage`（=学年）へ変換。
- **学年の壁（文法）**：子の **`gradeCeiling`（GrammarStage）を超える文法は出さない**。壁の内側なら**未習でもクイズ感覚でOK**（語彙の壁＝既知語プールとは別軸）。
- **語彙の壁**（既存 `SentenceSelection.gradeBand`／NGSL）と**文法の壁**（`GrammarGate`）を**両方**満たす文だけ出題。
- **不正解時に `explanationJa` を表示**（答え合わせ画面・事前作成の固定文。トンマナ安全）。
- タグ付けは当面**手付け**だが、CEFR-J のタグ語彙に沿うので恣意的にならない。

## 5. 出典
- 中学英語改訂（学年別文法）: https://www.manatera.com/blog/junior-high-school-english/
- 学習指導要領 付録9（小中高の言語材料）: https://www.mext.go.jp/content/1407196_27_1.pdf
- CEFR-J（公式）: https://cefrjapan.net/
- CEFR-J Grammar/Vocabulary Profile データ（商用可・要出典）: https://github.com/openlanguageprofiles/olp-en-cefrj
- Cambridge Young Learners (Pre-A1/A1/A2) Handbook: https://www.cambridgeenglish.org/Images/357180-starters-movers-and-flyers-handbook-for-teachers-2024.pdf

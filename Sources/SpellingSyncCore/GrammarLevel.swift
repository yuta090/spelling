import Foundation

/// 文法レベル（CEFR-J 基準・親には学年で表示）。
/// 調査と対応表: docs/grammar-level-cefrj-2026-06-28.md
///
/// 設計の二軸：
/// - **語彙の壁** … `SentenceItem.gradeBand`（NGSL）／`SentenceSelection`
/// - **文法の壁** … `GrammarPoint.stage`（CEFR-J）／`GrammarGate`（本ファイル）
/// 壁の内側なら未習の文法でも出題してよい（クイズ感覚）。不正解時は `explanationJa` を見せて学ばせる。

// MARK: - 文法段階（CEFR-J を基準・親には学年表示）

/// 文法の段階。CEFR-J のサブレベルに対応し、親には `gradeLabelJa`（学年）で見せる。
/// `rawValue` 昇順 = やさしい→むずかしい。
public enum GrammarStage: Int, Comparable, CaseIterable, Codable, Sendable {
    // 永続化（子の上限設定）で並べ替え事故が起きないよう raw 値を明示する。
    // 途中に段階を足すときは末尾に追加し、既存値は変えないこと。
    case intro1 = 0   // A1.1 / 小学校
    case intro2 = 1   // A1.2 / 小6〜中1
    case basic1 = 2   // A1.3 / 中1
    case basic2 = 3   // A2.1 / 中2
    case applied = 4  // A2.2 / 中2〜中3

    public static func < (lhs: GrammarStage, rhs: GrammarStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// CEFR-J のラベル（内部・開発者向け）。
    public var cefrJ: String {
        switch self {
        case .intro1: return "A1.1"
        case .intro2: return "A1.2"
        case .basic1: return "A1.3"
        case .basic2: return "A2.1"
        case .applied: return "A2.2"
        }
    }

    /// 親に見せる学年表示（学習指導要領の目安）。子の画面には出さない。
    public var gradeLabelJa: String {
        switch self {
        case .intro1: return "小学校"
        case .intro2: return "小6〜中1"
        case .basic1: return "中1"
        case .basic2: return "中2"
        case .applied: return "中2〜中3"
        }
    }
}

// MARK: - 文法項目（タグ）

/// 文の文法タグ。1文に1つ付け、`stage` で学年の壁を判定する。
/// `explanationJa` は不正解時に出す**事前作成の固定解説**（トンマナ安全のため都度生成しない）。
/// ※ 配置・文言は暫定。CEFR-J 生データ＋学習指導要領で運用しながら微調整する。
public enum GrammarPoint: String, CaseIterable, Codable, Sendable {
    // --- intro1 (A1.1 / 小学校) ---
    case beVerb
    case demonstratives
    case articles
    case canModal
    case pronouns
    case plurals
    case presentSimple
    // --- intro2 (A1.2 / 小6〜中1) ---
    case presentContinuous
    case negation
    case yesNoQuestion
    case beVerbPast
    case frequencyAdverb
    // --- basic1 (A1.3 / 中1) ---
    case pastSimple
    case comparativeEr
    case imperative
    case whQuestion
    // --- basic2 (A2.1 / 中2) ---
    case willGoingTo
    case shouldModal
    case passiveVoice
    case infinitive
    case indirectSpeech
    // --- applied (A2.2 / 中2〜中3) ---
    case haveToNeedTo
    case gerund
    case presentPerfect

    /// 文法段階（=学年の壁）。
    public var stage: GrammarStage {
        switch self {
        case .beVerb, .demonstratives, .articles, .canModal, .pronouns, .plurals, .presentSimple:
            return .intro1
        case .presentContinuous, .negation, .yesNoQuestion, .beVerbPast, .frequencyAdverb:
            return .intro2
        case .pastSimple, .comparativeEr, .imperative, .whQuestion:
            return .basic1
        case .willGoingTo, .shouldModal, .passiveVoice, .infinitive, .indirectSpeech:
            return .basic2
        case .haveToNeedTo, .gerund, .presentPerfect:
            return .applied
        }
    }

    /// 親・管理向けの文法名（日本語）。
    public var titleJa: String {
        switch self {
        case .beVerb: return "be動詞（am/is/are）"
        case .demonstratives: return "This / That"
        case .articles: return "a / an / the"
        case .canModal: return "can（〜できる）"
        case .pronouns: return "代名詞"
        case .plurals: return "複数形"
        case .presentSimple: return "現在形"
        case .presentContinuous: return "現在進行形（〜している）"
        case .negation: return "否定文（〜ない）"
        case .yesNoQuestion: return "Yes/No の疑問文"
        case .beVerbPast: return "be動詞の過去（was/were）"
        case .frequencyAdverb: return "頻度の副詞"
        case .pastSimple: return "一般動詞の過去（-ed）"
        case .comparativeEr: return "比較級（-er）"
        case .imperative: return "命令文"
        case .whQuestion: return "疑問詞（why/where/when/how）"
        case .willGoingTo: return "未来（will / be going to）"
        case .shouldModal: return "should（〜したほうがいい）"
        case .passiveVoice: return "受動態（〜される）"
        case .infinitive: return "不定詞（to + 動詞）"
        case .indirectSpeech: return "間接話法"
        case .haveToNeedTo: return "have to / need to（〜しなければ）"
        case .gerund: return "動名詞（〜ing）"
        case .presentPerfect: return "現在完了（have + 過去分詞）"
        }
    }

    /// 不正解時に見せる、子向けの短い固定解説（暫定文言）。
    public var explanationJa: String {
        switch self {
        case .beVerb:
            return "「〜です」は be動詞。I は am、you と複数は are、それ以外は is。"
        case .demonstratives:
            return "近くのものは This（これ）、遠くのものは That（あれ）。"
        case .articles:
            return "数えられる1つには a。母音の音の前は an。決まったものには the。"
        case .canModal:
            return "can のあとは動詞のもとの形。He can swim. のように s はつけない。"
        case .pronouns:
            return "I → my → me のように、主語・持ち主・目的語で形が変わる。"
        case .plurals:
            return "2つ以上は s をつける。box → boxes のように es になる語もある。"
        case .presentSimple:
            return "いつもの事は現在形。he / she / it のときは動詞に s をつける。"
        case .presentContinuous:
            return "be動詞 + 〜ing で「今〜している」。I am playing."
        case .negation:
            return "「〜ない」は、be動詞は not、一般動詞は don't / doesn't を使う。"
        case .yesNoQuestion:
            return "Are you 〜? / Do you 〜? で始める。最後は声を上げて読む。"
        case .beVerbPast:
            return "am / is は was、are は were。「〜だった」。"
        case .frequencyAdverb:
            return "always → usually → often → sometimes の順でよくする度合い。ふつう動詞の前。"
        case .pastSimple:
            return "終わった事は ed をつける。play → played。go → went など形が変わる語も。"
        case .comparativeEr:
            return "「もっと〜」は er。bigger / faster。than で比べる相手を言う。"
        case .imperative:
            return "命令文は動詞のもとの形で始める。Look! / Don't run. 主語はいらない。"
        case .whQuestion:
            return "「なぜ・どこ・いつ・どうやって」を文の最初に置いてたずねる。"
        case .willGoingTo:
            return "これからの事は will + 動詞、または be going to + 動詞。"
        case .shouldModal:
            return "should は「〜したほうがいい」。あとは動詞のもとの形。"
        case .passiveVoice:
            return "be動詞 + 過去分詞で「〜される」。It is made in Japan."
        case .infinitive:
            return "to + 動詞で「〜すること／〜するため」。I want to play."
        case .indirectSpeech:
            return "人の言葉を自分の文に入れる。She said (that) she was happy."
        case .haveToNeedTo:
            return "have to / need to は「〜しなければならない」。あとは動詞のもとの形。"
        case .gerund:
            return "動詞 + ing で「〜すること」。I like swimming."
        case .presentPerfect:
            return "have / has + 過去分詞で「今までに〜した」。I have finished."
        }
    }
}

// MARK: - 文法の壁

/// 文法の壁（学年上限）。子の `ceiling`（GrammarStage）を超える文法は出さない。
/// 壁の内側なら未習でも出題可（クイズ感覚）。タグ無しの文は文法制約にかからない。
public enum GrammarGate {
    /// この文を出してよいか（文の文法段階 ≤ 上限）。
    public static func isAllowed(_ item: SentenceItem, ceiling: GrammarStage) -> Bool {
        guard let stage = item.grammarStage else { return true }
        return stage <= ceiling
    }

    /// 上限以内の文だけを残す（順序は保持）。
    public static func eligible(_ items: [SentenceItem], ceiling: GrammarStage) -> [SentenceItem] {
        items.filter { isAllowed($0, ceiling: ceiling) }
    }
}

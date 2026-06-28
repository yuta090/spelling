import Foundation

/// 出題プール（生成文）の絞り込みを1か所に集約する純ロジック。
///
/// 設計（`docs/age-tiered-generation-spec-2026-06-29.md` §5/§10、[[content-schema-v2-architecture]]）：
/// - 子の段階 → 出題制約（語彙band/文法天井/漢字/ジャンル/i+1）を1つの値に。
/// - `PuzzleContentBuilder` の入口で**プールにだけ**効かせる（必須＝登録語そのものには効かせない）。
/// - **親登録語は tier 例外**：上限超えの原因が登録語だけなら band 表で救済して残す。
/// - i+1 は登録語を「許される未知語1語」として数える（未知語の総数 ≤ maxNewLemmasPerSentence）。

// MARK: - ジャンル

public enum Genre: String, Codable, Sendable, Equatable, CaseIterable {
    /// 役立つ日常文（既定）。
    case useful
    /// ユーモア（プール限定・親トグル）。
    case humor
    /// 物語（PD 翻案）。
    case story
}

// MARK: - 出題制約

public struct ContentPolicy: Equatable, Sendable {
    /// 語彙の壁（ゆるい上限・NGSL band）。
    public var targetBand: Int
    /// 文法の天井（これを超える文法は出さない）。
    public var grammarCeiling: GrammarStage
    /// 漢字の壁（和訳に使ってよい配当学年の上限。0=ひらがな主体）。
    public var maxKanjiGrade: Int
    /// 出してよいジャンル（humor トグルを反映）。
    public var enabledGenres: Set<Genre>
    /// 1文に許す新出（子の未知）語の上限＝i+1（既定 1）。
    public var maxNewLemmasPerSentence: Int

    public init(targetBand: Int, grammarCeiling: GrammarStage, maxKanjiGrade: Int,
                enabledGenres: Set<Genre>, maxNewLemmasPerSentence: Int) {
        self.targetBand = targetBand
        self.grammarCeiling = grammarCeiling
        self.maxKanjiGrade = maxKanjiGrade
        self.enabledGenres = enabledGenres
        self.maxNewLemmasPerSentence = maxNewLemmasPerSentence
    }
}

extension ContentPolicy {
    /// プール候補を制約で絞る純関数。順序は保持。
    /// - Parameters:
    ///   - knownLemmas: その段階で子が既知の語（i+1 判定に使う）。
    ///   - exemptRegisteredLemmas: 登録語（tier 例外＝band で救済する対象）。
    ///   - bandOf: 語→band の表（tier 例外の再計算に使う。未指定なら救済しない）。
    public static func admissiblePool(
        _ items: [SentenceItem],
        policy: ContentPolicy,
        knownLemmas: Set<String>,
        exemptRegisteredLemmas: Set<String> = [],
        bandOf: [String: Int] = [:]
    ) -> [SentenceItem] {
        items.filter { item in
            isAdmissible(item, policy: policy, knownLemmas: knownLemmas,
                         exemptRegisteredLemmas: exemptRegisteredLemmas, bandOf: bandOf)
        }
    }

    static func isAdmissible(
        _ item: SentenceItem,
        policy: ContentPolicy,
        knownLemmas: Set<String>,
        exemptRegisteredLemmas: Set<String>,
        bandOf: [String: Int]
    ) -> Bool {
        // ジャンル（nil は useful 扱い）。
        let genre = item.genre ?? .useful
        guard policy.enabledGenres.contains(genre) else { return false }

        // 文法の天井（タグ無しは通す）。
        if let stage = item.grammarStage, stage > policy.grammarCeiling { return false }

        // 漢字の壁（和訳の漢字が許可学年以内か）。
        guard KanjiLevelGate.isWithin(item.ja, maxGrade: policy.maxKanjiGrade) else { return false }

        // 語彙band：まずビルド時の gradeBand で判定。超過時は登録語(例外)を除いた band で救済を試みる。
        // ⚠ 安全側＝非例外語の band が1つでも不明なら救済しない（不明を“安全”と誤判定しない）。
        if item.gradeBand > policy.targetBand {
            guard !exemptRegisteredLemmas.isEmpty, !bandOf.isEmpty else { return false }
            let nonExempt = item.contentLemmas.filter { !exemptRegisteredLemmas.contains($0) }
            var effectiveBand = 0
            for lemma in nonExempt {
                guard let b = bandOf[lemma] else { return false } // 非例外語の band 不明＝救済しない
                effectiveBand = max(effectiveBand, b)
            }
            // nonExempt が空＝上限超えの原因は登録語のみ → effectiveBand 0 で通る。
            guard effectiveBand <= policy.targetBand else { return false }
        }

        // i+1：1文の新出（子の未知）語の**異なり数**が上限以内か。
        // - 重複語を二重計上しない（distinct）。
        // - 文中に登録語があれば、たとえ knownLemmas にあっても必ず +1 を消費する（登録語＝許される未知語1）。
        let distinct = Set(item.contentLemmas)
        let newLemmas = distinct.filter { lemma in
            !knownLemmas.contains(lemma) || exemptRegisteredLemmas.contains(lemma)
        }
        guard newLemmas.count <= policy.maxNewLemmasPerSentence else { return false }

        return true
    }
}

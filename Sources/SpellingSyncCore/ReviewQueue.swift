import Foundation

/// 1項目の復習状態（**活動非依存**）。`id` は語・文・文法点など、活動側の意味は問わない。
/// 卒業判定は Leitner 箱（`SRSScheduler` を再利用）、再出題タイミングは **ステップ番号**
/// （カレンダー非依存）で刻む。永続化のため `Codable`。
/// 設計判断: 卒業=Leitner箱 / タイミング=ステップ基準 / キューは活動ごとに分離。
public struct ReviewItemState: Equatable, Sendable, Codable, Identifiable {
    /// 復習対象の項目ID。
    public var id: UUID
    /// 1〜5（Leitner）。大きいほど定着＝再出題間隔が長い。
    public var box: Int
    /// 最後にこの項目を出題したステップ番号。
    public var lastSeenStep: Int
    /// 復習キューに最初に積まれたステップ（安定ソート用・以後不変）。
    public var addedAtStep: Int

    public init(id: UUID, box: Int = SRSScheduler.minBox, lastSeenStep: Int, addedAtStep: Int) {
        self.id = id
        self.box = box
        self.lastSeenStep = lastSeenStep
        self.addedAtStep = addedAtStep
    }
}

/// 活動非依存の「間違い復習」エンジン（**純粋ロジック**）。
///
/// スペル練習・文法クイズなど、どの活動でも同じロジックを使えるよう項目を `UUID` で抽象化する。
/// 「間違えた項目を、1度の正解で即消すのではなく、今後のステップに少数（+1〜2問）ずつ
/// 追加問題として自然に混ぜる」を担う。`Date()`/乱数を使わず、入力（states / step / cap）から
/// 決定的に結果を返す（同期コアの方針）。I/O・永続化・ステップ番号の採番はアプリ側。
///
/// 使い方（活動ごとに別の `[ReviewItemState]` とステップ番号を持つ）:
/// 1. 出題前: `selectForInjection(_:currentStep:cap:)` で追加問題（復習）を最大 cap 件得る。
/// 2. 解答後: 各項目の正誤を `apply(_:itemID:correct:step:)` で反映する。
/// 3. 任意: `pruneMastered(_:currentStep:)` で卒業済みを掃除する。
public enum ReviewQueue {
    /// box → 「次に再出題するまで空けるステップ数」。Leitner の間隔を **ステップ** に写像する。
    /// box1 は次のステップ、box が上がるほど間隔が伸び、box5 を越えると mastered（卒業）。
    public static func stepInterval(box: Int) -> Int {
        switch min(max(box, SRSScheduler.minBox), SRSScheduler.maxBox) {
        case 1: return 1
        case 2: return 2
        case 3: return 3
        case 4: return 5
        default: return 8
        }
    }

    /// 習得済み（出題終了＝卒業）か。box5 に到達し、その間隔ぶんステップが進んだら卒業。
    public static func isMastered(_ state: ReviewItemState, currentStep: Int) -> Bool {
        guard state.box >= SRSScheduler.maxBox else { return false }
        return currentStep - state.lastSeenStep >= stepInterval(box: SRSScheduler.maxBox)
    }

    /// このステップで再出題すべき（due）か。mastered は false。
    public static func isDue(_ state: ReviewItemState, currentStep: Int) -> Bool {
        if isMastered(state, currentStep: currentStep) { return false }
        return currentStep - state.lastSeenStep >= stepInterval(box: state.box)
    }

    /// 1回の解答結果をキューに反映する **単一エントリポイント**（全活動共通）。
    /// - `correct == false`: 未登録なら box1 で新規登録、登録済みなら box1 にリセット。
    /// - `correct == true` : 未登録なら何もしない（一度も間違えていない語は復習に積まない）、
    ///   登録済みなら box+1（`SRSScheduler.nextBox`）。
    /// 登録済み項目は `lastSeenStep` を `step` に前進させる。同 id は常に1件（冪等）。
    ///
    /// 呼び出し側の契約（純粋関数として強制はしない）:
    /// - `step` は活動ごとに **単調増加** で渡す（過去の step を渡すと `lastSeenStep` が巻き戻る）。
    /// - 1つの項目に対して **1ステップにつき高々1回** 呼ぶ（同一ステップで複数回呼ぶと box が多重に上がる）。
    public static func apply(
        _ states: [ReviewItemState],
        itemID: UUID,
        correct: Bool,
        step: Int
    ) -> [ReviewItemState] {
        var out = states
        if let i = out.firstIndex(where: { $0.id == itemID }) {
            out[i].box = SRSScheduler.nextBox(current: out[i].box, correct: correct)
            out[i].lastSeenStep = step
        } else if !correct {
            out.append(ReviewItemState(id: itemID, box: SRSScheduler.minBox, lastSeenStep: step, addedAtStep: step))
        }
        return out
    }

    /// due な項目を出題優先度順に整列して返す（`selectForInjection`/`composeRound` の共通土台）。
    /// 「**自分の予定からの超過（overdue）が大きい順** → addedAtStep の古い順 → id」で安定整列。
    /// 超過は box ごとの間隔で正規化するので、未定着＝低 box（間隔が短い）の項目が相対的に優先される。
    private static func dueSorted(_ states: [ReviewItemState], currentStep: Int) -> [ReviewItemState] {
        states
            .filter { isDue($0, currentStep: currentStep) }
            .sorted { lhs, rhs in
                // 予定再出題ステップ（lastSeenStep + 間隔）からどれだけ過ぎたか。大きいほど先。
                let lOver = currentStep - (lhs.lastSeenStep + stepInterval(box: lhs.box))
                let rOver = currentStep - (rhs.lastSeenStep + stepInterval(box: rhs.box))
                if lOver != rOver { return lOver > rOver }
                if lhs.addedAtStep != rhs.addedAtStep { return lhs.addedAtStep < rhs.addedAtStep }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// このステップで「追加問題」として注入する復習項目を最大 `cap` 件返す。
    /// 優先度順（`dueSorted`）に上位 cap 件。`cap <= 0` は空。
    public static func selectForInjection(
        _ states: [ReviewItemState],
        currentStep: Int,
        cap: Int
    ) -> [ReviewItemState] {
        guard cap > 0 else { return [] }
        return Array(dueSorted(states, currentStep: currentStep).prefix(cap))
    }

    /// 1ラウンドの出題ID順を組む（**活動共通**）。`base`（通常出題、順序維持）の後ろに、
    /// このステップで due な復習項目を「追加問題」として最大 `cap` 件足して返す。
    /// - base に既に含まれるIDは二重に足さない（cap は **新たに足す件数** に効く）。
    /// - 返り値: `base` の順 ＋ 追加した復習（overdue 優先順）。`cap <= 0` は base のみ。
    public static func composeRound(
        base: [UUID],
        states: [ReviewItemState],
        currentStep: Int,
        cap: Int
    ) -> [UUID] {
        guard cap > 0 else { return base }
        let baseSet = Set(base)
        let injected = dueSorted(states, currentStep: currentStep)
            .lazy
            .map(\.id)
            .filter { !baseSet.contains($0) }
            .prefix(cap)
        return base + Array(injected)
    }

    /// 習得済み（卒業）項目を取り除く（任意の掃除）。
    public static func pruneMastered(_ states: [ReviewItemState], currentStep: Int) -> [ReviewItemState] {
        states.filter { !isMastered($0, currentStep: currentStep) }
    }
}

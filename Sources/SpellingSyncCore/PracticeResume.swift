// MARK: - 練習セッションの再開（「やめた語から続ける」）

/// 中断した練習を「やめた語」から再開するための純粋ロジック。
///
/// 再開状態はセッション開始時の語ID列（順序つき）と、そのときのインデックスを持つ。
/// 再開時にその都度**練習選択を計算し直すと**、練習による `firstIntroducedAt` スタンプや
/// 抑制（マスター済み除外）で選択集合が揺れて語ID列が食い違い、再開が破棄されて
/// 1問目からやり直しになっていた。
///
/// ここでは選択を計算し直さず、**保存した語ID列のうちアクティブに残っている語だけ**で
/// セッションを再構築する。抑制・1日上限は語をアクティブから消さない（練習選択から外すだけ）ため、
/// これらの揺れに影響されず必ず「やめた語」から続けられる。親が語を削除した場合だけ、
/// 消えた語を飛ばしてインデックスを前詰めし、生き残りから続行する。
public enum PracticeResume {
    /// 保存済み再開状態を、いまアクティブな語IDだけで再構築する。
    /// - Parameters:
    ///   - savedWordIDs: セッション開始時の順序つき語ID列。
    ///   - savedIndex: やめた地点の語インデックス（`savedWordIDs` の添字）。
    ///   - availableIDs: いまアクティブな語IDの集合。
    /// - Returns: 再開に使う語ID列と補正後インデックス。続行不能（生き残り無し・範囲外・空）なら nil。
    public static func resolve<ID: Hashable>(
        savedWordIDs: [ID],
        savedIndex: Int,
        availableIDs: Set<ID>
    ) -> (wordIDs: [ID], index: Int)? {
        guard !savedWordIDs.isEmpty, savedIndex >= 0, savedIndex < savedWordIDs.count else {
            return nil
        }
        let surviving = savedWordIDs.filter { availableIDs.contains($0) }
        guard !surviving.isEmpty else {
            return nil
        }
        // やめた地点より前で生き残っている語数 = 補正後インデックス（消えた語ぶん前詰め）。
        let before = savedWordIDs.prefix(savedIndex).reduce(into: 0) { count, id in
            if availableIDs.contains(id) { count += 1 }
        }
        let index = min(before, surviving.count - 1)
        return (surviving, index)
    }
}

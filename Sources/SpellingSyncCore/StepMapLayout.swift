import Foundation

/// ステップ選択「冒険マップ」（下＝スタート→上にスクロールで空へ登るすごろく道）の純ロジック。
///
/// SwiftUI / CoreGraphics 非依存（座標は `Double`）。描画側（iPadPrototype）で `CGPoint` に変換する。
/// 「ノードの状態判定」と「座標計算」だけをここに置き、テストで固める（仕様 §4・§9）。
public enum StepMapLayout {

    // MARK: - ノードの状態（done / current / upcoming）

    /// 1つのステップが地図上でどう見えるか。
    public enum NodeState: String, Sendable, Equatable {
        case done       // 今日できた（緑チェック）
        case current    // いまここ（必ず1つ・拍動＋アバター）
        case upcoming   // これから（淡く誘う）
    }

    /// 「いまここ」に当たるステップIDを **必ず1つ** に確定する。
    ///
    /// - Precondition: `orderedIDs` の要素は一意（重複なし）。アプリ側は `AppModel.makeWordSteps`
    ///   がステップグループのキーからIDを作るため一意性が保証される。重複があると `nodeStates`
    ///   が同一IDを複数 `.current` にし得る（描画側 `ForEach(id:)` も不正になる）。
    ///
    /// 優先順位:
    /// 1. 選択中のステップが今日まだ終わっていなければ、それを current にする（子が今いる所）。
    /// 2. 今日まだ終わっていない最初（地図の下＝`orderedIDs` 先頭寄り）のステップ。
    /// 3. 全部終わっている場合は、選択中（あれば）／無ければ最後のステップ。
    ///
    /// - Parameters:
    ///   - orderedIDs: 下（スタート）→上（最新）の順に並べたステップID。
    ///   - completedToday: 今日のぶんを終えたステップIDの集合。
    ///   - selectedID: いま子が選んでいるステップID（無ければ nil）。
    public static func currentStepID(
        orderedIDs: [String],
        completedToday: Set<String>,
        selectedID: String?
    ) -> String? {
        guard !orderedIDs.isEmpty else { return nil }
        if let sel = selectedID, orderedIDs.contains(sel), !completedToday.contains(sel) {
            return sel
        }
        if let firstIncomplete = orderedIDs.first(where: { !completedToday.contains($0) }) {
            return firstIncomplete
        }
        if let sel = selectedID, orderedIDs.contains(sel) { return sel }
        return orderedIDs.last
    }

    /// 各ステップの状態を `orderedIDs` と同じ順で返す。`current` は必ず1つだけ含まれる。
    public static func nodeStates(
        orderedIDs: [String],
        completedToday: Set<String>,
        selectedID: String?
    ) -> [NodeState] {
        let current = currentStepID(orderedIDs: orderedIDs, completedToday: completedToday, selectedID: selectedID)
        return orderedIDs.map { id in
            if id == current { return .current }
            if completedToday.contains(id) { return .done }
            return .upcoming
        }
    }

    // MARK: - 座標（データ駆動：ステップ配列→座標）

    /// 平面上の点（描画側で `CGPoint` に変換）。
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// 地図全体の高さ。ノードが増えるほど縦に伸びる（上に伸ばすだけで破綻しない）。
    /// - Parameters:
    ///   - groundPad: 一番下のノードと地面の間の余白。
    ///   - skyPad: 一番上のノードとゴール（空の上端）の間の余白。
    public static func contentHeight(count: Int, spacing: Double, groundPad: Double, skyPad: Double) -> Double {
        let n = max(count, 1)
        return groundPad + skyPad + Double(n - 1) * spacing
    }

    /// ノード1個の座標。`index 0` = 一番下（スタート／ステップ1）。index が増えると上（y が小さく）へ。
    /// x は左右ジグザグ（偶数=左 `leftFrac`／奇数=右 `rightFrac`）。
    public static func nodePoint(
        index: Int,
        width: Double,
        contentHeight: Double,
        spacing: Double,
        groundPad: Double,
        leftFrac: Double = 0.34,
        rightFrac: Double = 0.66
    ) -> Point {
        let x = (index % 2 == 0) ? width * leftFrac : width * rightFrac
        let y = contentHeight - groundPad - Double(index) * spacing
        return Point(x: x, y: y)
    }

    /// 全ノードの座標。
    public static func nodePoints(
        count: Int,
        width: Double,
        contentHeight: Double,
        spacing: Double,
        groundPad: Double,
        leftFrac: Double = 0.34,
        rightFrac: Double = 0.66
    ) -> [Point] {
        guard count > 0 else { return [] }
        return (0..<count).map {
            nodePoint(index: $0, width: width, contentHeight: contentHeight,
                      spacing: spacing, groundPad: groundPad, leftFrac: leftFrac, rightFrac: rightFrac)
        }
    }

    /// 小道（点線）のアンカー点列：`[地上アンカー] + 全ノード + [ゴール方向アンカー]`。
    /// ノードが増減しても、この配列を引き直すだけで道が自動で並び直る。
    public static func pathPoints(
        nodePoints: [Point],
        width: Double,
        contentHeight: Double,
        skyPad: Double,
        leftFrac: Double = 0.34
    ) -> [Point] {
        var pts: [Point] = [Point(x: width * leftFrac, y: contentHeight - 110)]
        pts.append(contentsOf: nodePoints)
        pts.append(Point(x: width * 0.5, y: skyPad - 110))
        return pts
    }
}

import Foundation

/// 練習ヒントに出す「意味（訳）」を決める純ロジック。
///
/// 単語リストは各語に訳 `promptText`（親の手入力・取り込み時の自動付与・コース訳）を保持している。
/// 一方で練習ヒントは従来、語の文字列から同梱辞書(EJDict)の第1語義を毎回引き直しており、
/// リスト表示の訳と食い違い、EJDict の簡潔/古い第1語義（例: lot→くじ）が出る不整合があった。
/// ここでは **保持している訳(promptText)を最優先**し、無いときだけ辞書の第1語義に落とす。
public enum MeaningResolver {
    /// - Parameters:
    ///   - promptText: 単語が保持する訳（手入力/取り込み/コース由来）。丸ごと尊重する（語義分割しない）。
    ///   - dictionaryGloss: 同梱辞書(EJDict)の生の訳（複数語義を含みうる）。フォールバック時のみ第1語義を切り出す。
    /// - Returns: 表示する意味。どちらも無ければ nil。
    public static func resolve(promptText: String?, dictionaryGloss: String?) -> String? {
        if let p = promptText?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        if let g = dictionaryGloss?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            let sense = GlossFormatter.primarySense(g)
            return sense.isEmpty ? nil : sense
        }
        return nil
    }
}

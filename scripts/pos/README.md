# 品詞テーブル（おぼえる練習の英文フレーム用）

「おぼえる練習」で登録語を英文フレーム（`I like ___.` / `I can ___.` / `It is ___.`）に
載せるため、同梱辞書 `wordbank.sqlite` に英語の主品詞テーブル `pos` を持たせる。

```
pos(word TEXT PRIMARY KEY, pos TEXT NOT NULL)   -- word=小文字, pos ∈ {noun,verb,adjective}
```

品詞が引けない語（約6%）はフレームに載せず、UI 側で「意味＋綴り4択（文なし）」に
フォールバックする（破綻させない）。

## データ出典 / ライセンス

- **Moby Project — Part-of-Speech List**（Grady Ward）。**パブリックドメイン**。
- 取得元ミラー: [en-wl/wordlist](https://github.com/en-wl/wordlist) `pos/part-of-speech.txt`。
- アプリ内クレジット: 保護者メニュー → 設定 → クレジット に記載。

## 主品詞の決め方（多義語）

Moby はコードを主用法順に並べる傾向がある（`run=VitN`, `play=VtiNA`, `milk=NVitA`, `big=Av`）。
よって**コード列の左から最初に当たる品詞**を主品詞にする:

| コード | 主品詞 |
|--------|--------|
| `N` `p` `h` | noun |
| `V` `t` `i` | verb |
| `A` | adjective |

`v`（副詞）等は無視。さらに固有名詞（大文字始まり）より**小文字見出しを優先**する
（`Happy=N` ではなく `happy=A!` を採用）。

## 再生成手順

`word_pos.tsv` が**凍結された真実のソース**（差分が安定するよう語昇順・テキスト）。
アプリ用 sqlite はこれから組む。ビルド時はネット不要。

```sh
# 1) （任意・更新したい時だけ）Moby から word_pos.tsv を再生成 ※ネット必要
python3 scripts/pos/refresh_moby_pos.py

# 2) word_pos.tsv を wordbank.sqlite の pos テーブルに適用 ※ネット不要
python3 scripts/pos/apply_pos_to_wordbank.py
```

`refresh` は Moby ファイルの sha256 を検証する（上流が変わると停止）。意図的に更新する
ときは中身を確認して `EXPECTED_SHA256` を更新するか `--allow-sha-mismatch` を付ける。

## workflows/release_workflow.yml
GitHub Actions による自動リリース（タグ発行＋Release作成）を行うワークフロー。
- トリガー: main ブランチへの push
- 権限: contents: write（タグ/Release 作成に必要）
- 主なステップ:
    1. Checkout（fetch-depth:0 で全履歴・タグ取得）
    2. 必要ツールインストール（jq / curl）
    3. シェルスクリプトへの実行権限付与
    4. Git ユーザー設定（bot 名義）
    5. bump-and-release.sh 実行（SemVer 判定→タグ→Release API）
- 目的: コミットメッセージ規約に基づきバージョン番号を自動インクリメントし、人的オペレーションを削減

### バージョン判定ロジック（スクリプト連携）
- BREAKING CHANGE / feat / その他（patch）で優先度: major > minor > patch
- 最終タグ取得失敗時は v0.0.0 を初期値にする

---

## scripts/bump-and-release.sh
自動バージョンバンピング + タグ作成 + GitHub Release API 呼び出しを一括処理する Bash スクリプト。
- 前提環境変数:
    - GITHUB_REPOSITORY（owner/repo）
    - GITHUB_TOKEN（認証用）
- 主処理フロー:
    1. 既存タグ取得（保険として git fetch --tags）
    2. 最新タグから HEAD までのコミット走査
    3. Conventional Commits / BREAKING CHANGE 判定で bump 種別決定
    4. 新しい SemVer を計算（major/minor/patch）
    5. 重複タグ存在チェック（競合回避）
    6. 注釈付きタグ作成 & push
    7. コミット一覧を簡易整形し Release 本文生成
    8. GitHub API (curl + jq) で Release 作成
- 防御的実装:
    - タグ存在時は再作成せず終了
    - Release API 応答が空のとき警告表示
- 利点: 外部ライブラリを極力使わない軽量運用

### バンプ判定詳細
- コミット本文中文字列: BREAKING CHANGE → major
- 例: feat!: などの '!' を含むヘッダー → major
- ヘッダーが feat: / feat( で始まる → minor
- 上記以外 → patch

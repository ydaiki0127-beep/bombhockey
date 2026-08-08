# ボムホッケー iPhone 導入ガイド

> 作成日: 2026-08-08
> 状態: ✅ **署名なし.ipaのビルドに成功**（GitHub Actions）

---

## 1. 現在の状況

| ステップ | 状態 |
|---|---|
| iOSエクスポートプリセット作成 | ✅ 完了 |
| App Store Team ID エラー回避 | ✅ 完了 |
| CIワークフローで署名なし.ipaビルド | ✅ **成功**（`build/ipa/bombhockey-unsigned.ipa` 29MB） |
| リポジトリ | ✅ `https://github.com/ydaiki0127-beep/bombhockey` |
| SideloadlyでiPhoneへインストール | ⏳ あなたの作業（7日ごとの再署名） |

---

## 2. 修正した内容（前セッションのエラー原因）

### エラー
```
ERROR: Cannot export project with preset "iOS" due to configuration errors:
App Store Team ID が指定されていません。
```

### 原因と修正
Godot **4.8 系**では、Apple共通のエクスポート実装（`EditorExportPlatformAppleEmbedded`）に
リファクタリングされ、オプションのキー名が変更されていました。

| 項目 | Godot 4.7 以前 | Godot 4.8 以降（本プロジェクト） |
|---|---|---|
| App Store Team ID | `application/signing_team_id` | **`application/app_store_team_id`** |
| コード署名無効化 | `application/codesign_disable` | 廃止（`export_method` / `code_sign_identity` に置換） |

`export_presets.cfg` の `[preset.1.options]` に以下を設定：

```ini
application/app_store_team_id="AAAAAAAAAA"        ; 10文字のダミーTeam ID（必須チェック通過用）
application/export_method_release=0
application/code_sign_identity_release="-"        ; 署名IDをad-hoc化（証明書なしでもdylib署名が成功）
application/export_project_only=true               ; プロジェクト生成のみでビルドをスキップ
```

> `AAAAAAAAAA` はダミー値。Xcode GUIでビルドする場合は、Teamを自分のApple IDに変更すると
> `DEVELOPMENT_TEAM` と署名IDが自動的に書き換わります。

### エクスポートコマンド（Windows）
```bash
cd "C:\Users\ydaik\作成したゲーム\air-hockey"
"C:\Users\ydaik\ソフトウェア\Godot_v4.8-dev2_win64.exe\Godot_v4.8-dev2_win64_console.exe" --headless --export-release "iOS"
```

---

## 3. iPhone に導入する方法（3つの選択肢）

> ⚠️ **重要な制約**: `.ipa` / `.app` のビルドは **macOS + Xcode でしか行えません**。
> Windowsからは「Xcodeプロジェクトの生成」までしかできません。

### 選択肢A: Mac を用意する（無料・おすすめ）
自分/家族/友人/学校のMacを使う方法。Apple IDがあれば**無料で自分のiPhoneにインストール可能**（7日間有効、期限切れで再インストール）。

1. `build/ios/` フォルダをMacにコピー（USBメモリ / AirDrop / クラウド）
2. Macで `bombhockey.xcodeproj` をXcodeで開く
3. メニューの **Signing & Capabilities** で Team を自分の Apple ID に変更
   - （`DEVELOPMENT_TEAM = AAAAAAAAAA` が Xcode で自動的に書き換わる）
4. iPhoneをUSBでMacに接続し、実行デバイスにiPhoneを選択
5. ▶ Run を押すとビルド→自動でiPhoneにインストール

**注意**: iPhoneの「設定」→「一般」→「VPNとデバイス管理」で開発者証明書を信頼する操作が必要な場合あり。

### 選択肢B: 無料のクラウドCIでビルド（Mac不要）
GitHub Actions の macOS ランナーを使う方法。**ワークフローファイルは作成済み**（`.github/workflows/ios.yml`）。

- リポジトリを GitHub にプッシュ → Actions タブ → **「iOS ビルド」→ Run workflow** で実行
- macOSランナー上で: Godot 4.8-dev2 エクスポート → `xcodebuild`（署名なし）→ `.ipa` にパッケージング → 成果物アップロード
- 詳細手順は **セクション6** 参照

- **注意**: 生成される `.ipa` は署名なし。そのままではインストール不可のため、**Sideloadlyで無料Apple ID署名してインストール**します（セクション6の手順6）。
- 有料のApple Developer Program（年$99）があればCI上で署名まで完結でき、`.ipa` を直接iPhoneにインストールできます（証明書とプロビジョニングプロファイルの設定が必要）。

### 選択肢C: Codemagic などのクラウドMacサービス
無料枠あり。Apple ID/Developerアカウントを連携して署名済み `.ipa` を生成可能。

---

## 4. Mac・開発者アカウントが無い場合の選択肢（2026-08 調査時点）

> 前提: `.ipa`/`.app` のビルドは macOS + Xcode が必須。
> 「Macが無い」場合の代替手段は以下の通り。

### 選択肢D: Ubuntu上で仮想Mac（OSX-KVM）を立ててビルド（自己責任・EULA違反）

- `kholia/OSX-KVM`（オープンソース）でUbuntu上にmacOSをQEMU/KVMで起動 → Xcodeをインストールしてビルド
- **2026年現在もメンテナンスされており実現可能**（macOS Sonoma/Sequoia対応）
- 要件: CPUのAVX2 + 仮想化支援（VT-x/SVM）、RAM 16〜32GB、NVMe SSD 128〜256GB以上
- 注意点:
  - **Apple EULA違反**（macOSはApple製ハードウェアでのみ実行可能。自己責任）
  - VM内ではMetal/GPUアクセラレーションが効かずiOSシミュレータは使い物にならないが、実機ビルドは問題ない
  - iPhoneのUSBパススルーは環境依存（失敗時はUSB Network Gate等でネットワーク経由USB共有）
  - Apple IDでのログインにシリアル番号の偽装が必要な場合があり、アカウント停止リスクあり

### 選択肢E: クラウドCIで.ipaを生成 → Sideloadlyで無料署名インストール（推奨）

- GitHub Actions の macOS ランナーで `.ipa` をビルド（実Macがクラウド上で動く）
- Windows版 **Sideloadly** で無料Apple ID署名してiPhoneにインストール
- 制限: 無料Apple IDは **7日ごとの再署名** と **同時3アプリまで**。サイドロード専用のサブApple ID作成が推奨
- GitHub Actions: リポジトリをpublicにすればmacOS実行時間も無料枠内

### 選択肢F: TrollStore（Apple ID不要の永続インストール）

- **対応iOS: 14.0〜16.6.1 / 17.0 のみ**。iOS 17.0.1以降・18/19世代は利用不可
- 対応しているiPhoneなら、無署名アプリをMacなしでインストール可能（ただしビルド自体は要Mac/CI）

---

## 5. よくある追加事項

- **シミュレータ**: このゲームは「GL Compatibility」レンダラーなので、iOSシミュレータでも動作します（Compatibilityのみシミュレータ対応）。
- **再エクスポート**: ゲームを変更したら、GitHub Actionsでワークフローを再実行するだけで新ビルドが作られます。
- **Bundle ID**: `com.bombhockey.game` が設定済み。ユニークなIDならこのままでOK。

---

## 6. 具体的な手順（GitHub Actions + Sideloadly）

### 手順1: GitHub リポジトリを作成・プッシュ

1. [github.com](https://github.com) でアカウント作成（無料）→ **New repository** を作成
   - リポジトリ名: `bombhockey` など（**public** にすること。private だと macOS ランナーの無料枠が使えません）
   - 初期化（README等）は不要（既存プロジェクトをプッシュするため）
2. このプロジェクトをプッシュ:
```bash
cd "C:\Users\ydaik\作成したゲーム\air-hockey"
git add -A
git commit -m "Bomb Hockey iOS 導入準備"
git branch -M main
git remote add origin https://github.com/<あなたのユーザー名>/bombhockey.git
git push -u origin main
```

### 手順2: ワークフローを実行（ゲームを更新するとき）

1. GitHubの **Actions** タブ → 左側の「**iOS ビルド（署名なし .ipa）**」→ **Run workflow**
2. 完了後、ジョブの**Artifacts**欄から `bombhockey-unsigned-ipa` をダウンロード

> 初回のビルドは**完了済み**で、`.ipa` は既に `build/ipa/bombhockey-unsigned.ipa` にあります。
> ゲームを変更したときだけ手順2を再実行してください。

### 手順3: Sideloadly で iPhone にインストール（あなたが行う最後の作業）

1. **Sideloadly**（無料・Windows対応）を https://sideloadly.io からダウンロードしてインストール
2. iPhone をUSBでPCに接続（初回は「このコンピュータを信頼しますか？」に「信頼」）
3. Sideloadly を起動し:
   - **IPA** 欄に `C:\Users\ydaik\作成したゲーム\air-hockey\build\ipa\bombhockey-unsigned.ipa` をドラッグ＆ドロップ
   - **Apple ID** 欄に無料のApple IDとパスワードを入力（サイドロード専用のサブApple IDを推奨）
   - **Start** をクリック → 署名・インストールが自動で進む
4. iPhoneの「設定」→「一般」→「VPNとデバイス管理」→ 開発者プロフィールを**信頼**
5. ホーム画面に「ボムホッケー」のアイコンが出現 → 起動！

### 手順4: 7日ごとの再署名

- 無料Apple IDの署名は**7日で失効**します。失効するとアプリが起動しなくなるため、
  Sideloadlyでもう一度同じ操作（手順3）を実行して再署名してください。
- Sideloadlyには自動更新機能もありますが、PC起動中のみ動作します。

### トラブルシューティング

| 症状 | 対処 |
|---|---|
| ワークフローが「Export」ステップで失敗 | ローカル（Windows）で同じエクスポートコマンドを実行して切り分け。`build/` フォルダが無い場合は `mkdir -p build/ios` を先に実行（CIは自動で実行済み） |
| `xcodebuild` で `MTLTensorDomain` / `CADynamicRange` が未定義 | 4.8-dev2テンプレートのmetal_cppが現行SDKに無いシンボルを参照する既知の不整合。CIでは `OTHER_LDFLAGS` に `-Wl,-U,_MTLTensorDomain -Wl,-U,_CADynamicRangeAutomatic -Wl,-U,_CADynamicRangeConstrainedHigh -Wl,-U,_CADynamicRangeHigh -Wl,-U,_CADynamicRangeStandard` を指定して回避（ゲームでは未使用のAPI） |
| `xcodebuild` ステップで署名エラー | ワークフローは `CODE_SIGNING_ALLOWED=NO` 済み。エラーログがあれば、画面をキャプチャして共有してください |
| iPhoneに「開発者を信頼できません」 | 設定→一般→VPNとデバイス管理で開発者証明書を信頼 |
| アプリが7日後に起動しない | Sideloadlyで再署名（手順3） |
| Sideloadlyで「署名エラー」でインストールできない | .ipa が正しくダウンロード・解凍されているか確認。再ダウンロードして再試行。サイドロード専用のサブApple IDを使うと成功率が上がります |
| privateリポジトリでmacOSランナーが使えない | リポジトリをpublicにする（無料枠はpublicのみ）|

> **参考**: 万一「Export」ステップがmacOS上で失敗する場合は、Godotのエクスポートだけを
> Linux/Windowsランナーで実行し、macOSランナーは`xcodebuild`のみ担当する2ジョブ構成に
> 変更することで回避できます（Linux/WindowsのエクスポートにはmacOS限定の署名処理が無いため）。

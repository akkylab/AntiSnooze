# AntiSnooze - 二度寝防止アラームアプリ

## 概要

**AntiSnooze**（「スヌーズ」に対抗するという意味）は、指定時間に起床し、その後の「二度寝」を防止するための特化型アラームアプリです。Apple Watchのモーションセンサーを利用して、ユーザーが再び横になったことを検知し、ウォッチの振動機能で起こし続けます。

## 主要機能

- Apple Watchの加速度センサーを用いた姿勢検知
- 横になっている状態（二度寝）の検知と継続的な振動アラート
- 歩行検知による起床確認機能
- カスタマイズ可能な振動強度（弱・中・強）
- 曜日ごとのアラーム繰り返し設定
- 起床成功時のお祝い画面表示
- アラーム履歴と二度寝カウントの記録

## 対応プラットフォーム

- **iPhone**: iOS 16以上
- **Apple Watch**: watchOS 9以上（開発時はwatchOS 11.4）

## システム構成

### アーキテクチャ

アプリは以下のコンポーネントで構成されています：

1. **iPhone用アプリ（ホストアプリ）**:
    - アラーム時刻の設定
    - 振動強度の設定
    - アラームの有効/無効切り替え
2. **Apple Watch用アプリ（コンパニオンアプリ）**:
    - モーションセンシング
    - 二度寝検知
    - 振動アラート制御
    - 歩行検知による起床確認
3. **共有データモデル**:
    - WatchConnectivityを使用したデバイス間通信
    - UserDefaultsを使用した設定の永続化

### 技術スタック

- **開発言語**: Swift 5.9以上
- **UI フレームワーク**: SwiftUI
- **使用フレームワーク**:
    - WatchKit
    - Core Motion (加速度センサー)
    - WatchConnectivity (iPhone-Watch間通信)
    - HealthKit (バックグラウンド実行)
    - UserNotifications (通知)

## 二度寝検知の仕組み

AntiSnoozeは複数の方法を組み合わせて二度寝を検知します：

1. **角度検知**:
    - 加速度センサーを使用し、デバイスの傾き角度を測定
    - 角度が140度以上で「横になっている」と判断
    - 角度が80度未満で「起き上がっている」と判断
    - ヒステリシス（履歴現象）を導入して誤検知を防止
2. **動き検知**:
    - 継続的な動きがあるかを監視
    - 短時間内に複数回の動きがあれば「起床」と判断
3. **歩行検知**:
    - CMPedometerを使用して歩数をカウント
    - 10秒間で8歩以上の歩行があれば「起床」と判断
4. **二度寝判定**:
    - アラーム時刻後に横になった状態が3分以上続くと「二度寝」と判断
    - 二度寝と判断したら振動を開始

## バックグラウンド実行

Apple Watchのバックグラウンド実行時間には制限があるため、以下の方法を組み合わせて対応しています：

1. **WKExtendedRuntimeSession**:
    - フォアグラウンドアプリがバックグラウンドに移行してもセンサーアクセスを維持
2. **HealthKit・ワークアウトセッション**:
    - バックグラウンド実行時間を延長
    - センサーの継続的なアクセスを確保

## プロジェクト構造

```
AntiSnooze/
  ├─ Shared/              // iPhone・Watch共通コンポーネント
  │   ├─ Model.swift           // データモデル
  │   ├─ SettingsManager.swift  // 設定管理
  │   └─ WatchConnectivityManager.swift // 通信管理
  │
  ├─ AntiSnooze/          // iPhone用アプリ
  │   ├─ Views/                // 画面
  │   │   ├─ MainView.swift         // メイン画面
  │   │   └─ AlarmSettingView.swift // 設定画面
  │   └─ ContentView.swift     // コンテンツビュー
  │
  └─ AntiSnoozeWatch Watch App/ // Watch用アプリ
      ├─ Views/                // 画面
      │   ├─ WatchMainView.swift    // メイン画面
      │   ├─ TimeSettingView.swift  // 時間設定画面
      │   └─ CongratulationsView.swift // お祝い画面
      └─ Services/             // サービス
          ├─ AlarmService.swift     // アラーム機能
          ├─ MotionDetectorService.swift // モーション検知
          └─ BackgroundModeManager.swift // バックグラウンド管理

```

## 開発者向け情報

### 開発環境

- **Xcode**: 15以上
- **macOS**: Sonoma以上
- **開発者アカウント**: Apple Developer Program（実機テスト・配布時に必要）

### ビルド手順

1. Xcodeでプロジェクトを開く
2. 開発者証明書でプロジェクトに署名
3. 接続されたiPhoneとApple Watchにビルド

### 重要な実装ポイント

- WatchConnectivityManagerを使ったiPhoneとApple Watch間のデータ同期
- MotionDetectorServiceの二度寝検知アルゴリズム
- バックグラウンド実行のためのHealthKit統合
- バッテリー消費を抑えるためのセンサー使用最適化

## 識別情報

- **Organization Identifier**: com.akkylab
- **Bundle Identifier**: com.akkylab.AntiSnooze

## ライセンス

このプロジェクトは独自ライセンスの下で公開されています。詳細はLICENSEファイルをご覧ください。

## 貢献について

バグ報告や機能リクエストは、GitHubのIssueトラッカーでお願いします。
プルリクエストも歓迎します。

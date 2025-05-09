# AntiSnooze - Anti-Snooze Alarm App

## Overview

**AntiSnooze** (meaning "to counter snooze") is a specialized alarm app designed to help users wake up at a set time and prevent falling back asleep afterward. It utilizes the Apple Watch’s motion sensors to detect if the user lies back down and continues to alert through haptic feedback.

## Key Features

- Posture detection using Apple Watch’s accelerometer  
- Detection of lying-down state (oversleep) with continuous haptic alerts  
- Wake-up confirmation via step detection  
- Customizable vibration intensity (low / medium / high)  
- Repeat alarm settings by day of the week  
- Congratulatory screen upon successful wake-up  
- Alarm history and oversleep count tracking  

## Supported Platforms

- **iPhone**: iOS 16 or later  
- **Apple Watch**: watchOS 9 or later (tested on watchOS 11.4)

## System Architecture

### Components

The app consists of the following components:

1. **iPhone App (Host App)**  
   - Alarm time configuration  
   - Vibration intensity settings  
   - Enable/disable alarm  

2. **Apple Watch App (Companion App)**  
   - Motion sensing  
   - Oversleep detection  
   - Haptic alert control  
   - Wake-up confirmation via step count  

3. **Shared Data Model**  
   - Device communication via WatchConnectivity  
   - Persistent settings using UserDefaults  

### Tech Stack

- **Programming Language**: Swift 5.9 or later  
- **UI Framework**: SwiftUI  
- **Frameworks Used**:  
  - WatchKit  
  - Core Motion (accelerometer)  
  - WatchConnectivity (device sync)  
  - HealthKit (background execution)  
  - UserNotifications (alerts)

## How Oversleeping is Detected

AntiSnooze combines multiple detection methods:

1. **Angle Detection**  
   - Measures tilt angle using accelerometer  
   - ≥140° → considered "lying down"  
   - <80° → considered "upright"  
   - Hysteresis logic prevents false detection  

2. **Motion Detection**  
   - Monitors for sustained movement  
   - Multiple movements in short intervals indicate wakefulness  

3. **Step Detection**  
   - Uses CMPedometer to count steps  
   - 8 or more steps within 10 seconds = "awake"  

4. **Oversleep Determination**  
   - If user remains lying for over 3 minutes after alarm time → "oversleep"  
   - Triggers haptic alerts  

## Background Execution

Due to watchOS background execution limits, the following methods are combined:

1. **WKExtendedRuntimeSession**  
   - Maintains sensor access after transitioning to background  

2. **HealthKit Workout Sessions**  
   - Extends background execution time  
   - Ensures continuous sensor availability  

## Project Structure
```
AntiSnooze/
├─ Shared/
│   ├─ Model.swift
│   ├─ SettingsManager.swift
│   └─ WatchConnectivityManager.swift
│
├─ AntiSnooze/
│   ├─ Views/
│   │   ├─ MainView.swift
│   │   └─ AlarmSettingView.swift
│   └─ ContentView.swift
│
└─ AntiSnoozeWatch Watch App/
├─ Views/
│   ├─ WatchMainView.swift
│   ├─ TimeSettingView.swift
│   └─ CongratulationsView.swift
└─ Services/
├─ AlarmService.swift
├─ MotionDetectorService.swift
└─ BackgroundModeManager.swift

```
## Developer Information

### Development Environment

- **Xcode**: Version 15 or later  
- **macOS**: Sonoma or later  
- **Developer Account**: Apple Developer Program (required for real device testing and distribution)

### Build Steps

1. Open the project in Xcode  
2. Sign the project with a valid developer certificate  
3. Build and run on connected iPhone and Apple Watch  

### Key Implementation Points

- Sync between iPhone and Watch via `WatchConnectivityManager`  
- Oversleep detection algorithm in `MotionDetectorService`  
- Background execution supported by HealthKit integration  
- Optimized sensor usage for battery efficiency  

## Identifiers

- **Organization Identifier**: com.akkylab  
- **Bundle Identifier**: com.akkylab.AntiSnooze

## Contributing

Please submit bug reports or feature requests via the GitHub issue tracker.  
Pull requests are welcome.

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

## 貢献について

バグ報告や機能リクエストは、GitHubのIssueトラッカーでお願いします。
プルリクエストも歓迎します。

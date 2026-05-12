# aws_ec2_tailscale

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

EC2 micro インスタンスを Tailscale **exit node** として動かし、Elastic IP を
擬似固定 IP として使う最小構成。**外部からのインバウンドポートは 0**。
SSH は Tailscale SSH 経由、緊急時は SSM Session Manager。

## 構成

```
[Your devices] ⇄ Tailscale (DERP/NAT traversal) ⇄ [EC2 exit node] → Internet (固定IP=EIP)
```

| 項目 | 値 |
|------|----|
| インスタンス | t4g.micro (ARM/Graviton) — 変更可 |
| AMI | Amazon Linux 2023 (arm64) — 最新を data lookup |
| ネットワーク | default VPC / default subnet |
| Public IP | Elastic IP (起動中インスタンスにアタッチ中は無料) |
| Security Group | **inbound 0 ルール** / egress 全許可 |
| シークレット | SSM Parameter Store (SecureString) |
| アクセス | Tailscale SSH + SSM Session Manager |
| 自動更新 | `dnf-automatic` 有効 |

ランニングコスト目安 (東京): **約 $4/月〜** (転送量で変動)

## 前提

- macOS / Linux のシェル
- `aws` CLI (v2) ログイン済み: `aws sts get-caller-identity` でアカウント確認
- `terraform` >= 1.6 (なければ `brew install hashicorp/tap/terraform` または `brew install opentofu` で `tofu` 使用)
- Tailscale アカウント

## セットアップ

### 1. Tailscale auth key を発行

[admin → Keys](https://login.tailscale.com/admin/settings/keys) で新規発行:

- **Reusable** ✓
- **Ephemeral** ✗
- **Pre-approved** ✓ (タグ必須)
- **Tags**: `tag:exit-node` (事前に ACL で定義: `"tagOwners": { "tag:exit-node": ["autogroup:admin"] }`)

### 2. `.env` に保存 (既存)

```
tailscale_authkey=tskey-auth-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

(プロジェクト直下の `.env`。`.gitignore` で除外済み)

### 3. デプロイ

```bash
./scripts/tf.sh init
./scripts/tf.sh plan
./scripts/tf.sh apply
```

`scripts/tf.sh` は `.env` を読んで `TF_VAR_tailscale_authkey` に変換してから
`terraform` を呼ぶラッパー。

### 4. Tailscale 管理コンソールで exit node を有効化

`apply` 直後はノード登録だけで exit node はまだ無効。
[admin → Machines](https://login.tailscale.com/admin/machines) で対象ホストを
開き、**Edit route settings → Use as exit node** を有効化。
(pre-approved key + ACL で自動化することも可能)

### 5. クライアント側で exit node を使う

```bash
# macOS / Linux
tailscale set --exit-node=aws-exit-node --exit-node-allow-lan-access=true

# 解除
tailscale set --exit-node=
```

iOS / Android はアプリの "Exit Node" メニューから選択。

確認:

```bash
curl ifconfig.me   # → terraform output の public_ip と一致するはず
```

## アクセス手段

### Tailscale SSH (常用)

```bash
tailscale ssh ec2-user@aws-exit-node
```

ポート 22 は **開いていない**。Tailscale ネットワーク内のみ。

### SSM Session Manager (緊急用)

```bash
aws ssm start-session --target $(./scripts/tf.sh output -raw instance_id) --region ap-northeast-1
```

Tailscale が壊れた・誤って `tailscale down` した時の保険。

## セキュリティのポイント

- **SG inbound 0 ルール**: 公開ポートなし。Tailscale は NAT 越えで動作 (DERP リレー or direct UDP)
- **IMDSv2 必須**: メタデータサービスのトークン化
- **SSM SecureString + 最小権限 IAM**: auth key を平文で持たない
- **EBS 暗号化**: 既定で有効化
- **自動更新**: `dnf-automatic.timer`

## クリーンアップ

```bash
./scripts/tf.sh destroy
```

Tailscale 側の machine は手動削除 ([admin → Machines](https://login.tailscale.com/admin/machines))。

## 免責事項 (Disclaimer)

- 本リポジトリは **個人の検証用サンプル** として公開しているもので、サポート・SLA・本番運用保証は一切ありません。
- 利用によって発生する **AWS の課金・通信料金・Tailscale の利用料**、その他いかなる費用も利用者の負担です。`destroy` し忘れによる継続課金にご注意ください。
- 本コードを利用したことで生じた **直接・間接の損害 (情報漏えい、サービス停止、課金事故、法的問題等) について作者は一切の責任を負いません**。MIT License の "AS IS" 条項に従います。
- 利用にあたっては **AWS 利用規約 / Tailscale Terms of Service / 各国法令** を遵守してください。exit node を経由した通信は最終的に当該 EC2 の IP から送信されるため、Tailscale や AWS のアクセプタブルユースポリシーに違反する用途には使用しないでください。
- 本リポジトリは **AWS / Tailscale 公式とは無関係** です。各サービス名は各社の商標です。
- 本番運用前に必ず **IAM 権限、SG、SSM パラメータの設計、auth key 管理方針、ログ取得要件** をご自身のセキュリティ基準で再評価してください。

## ライセンス

[MIT License](./LICENSE) — Copyright (c) 2026 morimorijap

## ディレクトリ

```
.
├── LICENSE                    # MIT
├── README.md
├── .env.example               # .env のテンプレート
├── .env                       # tailscale_authkey (git ignored)
├── scripts/
│   └── tf.sh                  # .env -> TF_VAR_* 変換ラッパー
└── terraform/
    ├── versions.tf
    ├── variables.tf
    ├── main.tf                # VPC data / SG / EIP / EC2
    ├── iam.tf                 # EC2 -> SSM 読み取り Role
    ├── ssm.tf                 # auth key 保管 (SecureString)
    ├── user_data.sh           # tailscale install + up
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── .gitignore
```

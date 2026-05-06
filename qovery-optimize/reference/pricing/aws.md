# AWS pricing reference

> **Source:** AWS public list price for `us-east-1`. On-Demand (no Savings Plans / RIs).
> Prices in USD. Other regions may vary by 5-20 %.
> Verify current pricing at <https://aws.amazon.com/ec2/pricing/on-demand/> before quoting savings.

## EC2 / EKS node instance types

| Instance | vCPU | Memory | Hourly | Monthly (~730h) |
|---|---|---|---|---|
| t3.small | 2 | 2 GB | $0.0208 | ~$15 |
| t3.medium | 2 | 4 GB | $0.0416 | ~$30 |
| t3.large | 2 | 8 GB | $0.0832 | ~$61 |
| t3.xlarge | 4 | 16 GB | $0.1664 | ~$121 |
| m5.large | 2 | 8 GB | $0.096 | ~$70 |
| m5.xlarge | 4 | 16 GB | $0.192 | ~$140 |
| m6i.large | 2 | 8 GB | $0.096 | ~$70 |
| m6i.xlarge | 4 | 16 GB | $0.192 | ~$140 |
| c5.large | 2 | 4 GB | $0.085 | ~$62 |
| r5.large | 2 | 16 GB | $0.126 | ~$92 |
| t3.medium (spot) | 2 | 4 GB | ~$0.013 | ~$9 (70 % savings) |
| m5.large (spot) | 2 | 8 GB | ~$0.035 | ~$26 (63 % savings) |

## RDS instance types

| Instance | vCPU | Memory | Hourly | Monthly |
|---|---|---|---|---|
| db.t3.micro | 2 | 1 GB | $0.017 | ~$12 |
| db.t3.small | 2 | 2 GB | $0.034 | ~$25 |
| db.t3.medium | 2 | 4 GB | $0.068 | ~$50 |
| db.t3.large | 2 | 8 GB | $0.136 | ~$99 |
| db.r6g.large | 2 | 16 GB | $0.260 | ~$190 |
| db.r6g.xlarge | 4 | 32 GB | $0.520 | ~$380 |
| RDS storage (gp3) | — | — | — | $0.115 / GB / month |
| RDS Multi-AZ surcharge | — | — | — | 2× compute cost |
| Aurora Serverless v2 | — | — | $0.12 / ACU-hour | Varies by load |

## ElastiCache

| Instance | vCPU | Memory | Hourly | Monthly |
|---|---|---|---|---|
| cache.t3.micro | 2 | 0.5 GB | $0.017 | ~$12 |
| cache.t3.medium | 2 | 3.09 GB | $0.068 | ~$50 |
| cache.t4g.medium | 2 | 3.09 GB | $0.054 | ~$40 (Graviton, 20 % cheaper) |
| cache.r6g.large | 2 | 13.07 GB | $0.209 | ~$153 |

## Infrastructure (fixed costs)

| Resource | Pricing | Monthly |
|---|---|---|
| EKS cluster fee | $0.10 / hr | $73 |
| NAT Gateway (per AZ) | $0.045 / hr + $0.045 / GB | $33 + data |
| ALB (Application Load Balancer) | $0.0225 / hr + LCU-hours | ~$16 + usage |
| NLB (Network Load Balancer) | $0.0225 / hr + NLCU-hours | ~$16 + usage |
| EBS gp3 | $0.08 / GB / month | Per volume |
| EBS io1 | $0.125 / GB / month + $0.065 / IOPS | Per volume |
| S3 Standard | $0.023 / GB / month | Per bucket |
| S3 Intelligent-Tiering | $0.023 / GB (freq) to $0.0036 / GB (archive) | Auto-tiered |
| CloudFront | $0.085 / GB (first 10 TB) | Per distribution |

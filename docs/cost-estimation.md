# Cost Estimation for S3 Deep Archive Transfer

## Pricing Components

### 1. Storage Costs

#### Deep Archive (Source)
- **Storage**: $0.00099 per GB/month
- **Minimum storage duration**: 180 days
- **Minimum object size**: 128KB

#### Standard (Target)
- **Storage**: $0.023 per GB/month
- No minimum duration
- No minimum size

#### Other Storage Classes (Target Options)

| Storage Class | Price/GB/Month | Minimum Duration | Use Case |
|---------------|----------------|------------------|----------|
| Standard | $0.023 | None | Frequent access |
| Intelligent-Tiering | $0.023 + $0.0025 monitoring | None | Unknown pattern |
| Standard-IA | $0.0125 | 30 days | Monthly access |
| One Zone-IA | $0.01 | 30 days | Recreatable data |
| Glacier Instant Retrieval | $0.004 | 90 days | Quarterly access |
| Glacier Flexible Retrieval | $0.0036 | 90 days | Annual access |

### 2. Restore (Retrieval) Costs

#### Deep Archive Restore Pricing

| Tier | Time | Cost per GB | Best For |
|------|------|-------------|----------|
| Bulk | 12 hours | $0.025 | Large datasets, non-urgent |
| Standard | 12 hours | $0.10 | Standard retrieval needs |

**Note**: Deep Archive does NOT have an Expedited tier.

#### Additional Restore Considerations
- **Restore request**: $0.10 per 1,000 requests
- **Data restoration**: Charges apply per GB
- **Temporary copy**: Restored data counts toward storage costs during retention period

### 3. Data Transfer Costs

#### Within AWS
- **Same region**: FREE
- **Cross-region**: $0.01-$0.02 per GB (varies by region)

#### Out of AWS
- **First 100 GB/month**: FREE
- **Next 10 TB/month**: $0.09 per GB
- **Next 40 TB/month**: $0.085 per GB
- **Over 150 TB/month**: $0.05 per GB

### 4. Request Costs

#### S3 API Requests

| Operation | Cost per 1,000 requests |
|-----------|-------------------------|
| PUT, COPY, POST, LIST | $0.005 |
| GET, SELECT | $0.0004 |
| Restore from Deep Archive | $0.10 |
| Lifecycle Transition | $0.01 |

## Example Scenarios

### Scenario 1: Small Dataset (10 GB)

**Requirements:**
- 10 GB in Deep Archive
- Restore with Bulk tier
- Copy to target account (same region)
- Keep in Standard storage

**Cost Breakdown:**

| Item | Calculation | Cost |
|------|-------------|------|
| Deep Archive storage (1 month) | 10 GB × $0.00099 | $0.01 |
| Bulk restore | 10 GB × $0.025 | $0.25 |
| Restore requests | 5 files × $0.10 / 1,000 | $0.00 |
| Data transfer (same region) | 10 GB × $0 | $0.00 |
| Target Standard storage (1 month) | 10 GB × $0.023 | $0.23 |
| **Total** | | **$0.49** |

### Scenario 2: Medium Dataset (100 GB)

**Requirements:**
- 100 GB in Deep Archive
- Restore with Bulk tier
- Copy to target account (same region)
- Keep in Intelligent-Tiering

**Cost Breakdown:**

| Item | Calculation | Cost |
|------|-------------|------|
| Deep Archive storage (1 month) | 100 GB × $0.00099 | $0.10 |
| Bulk restore | 100 GB × $0.025 | $2.50 |
| Restore requests | ~20 files × $0.10 / 1,000 | $0.00 |
| Data transfer (same region) | 100 GB × $0 | $0.00 |
| Target Intelligent-Tiering (1 month) | 100 GB × ($0.023 + $0.0025) | $2.55 |
| Copy requests | 20 × $0.005 / 1,000 | $0.00 |
| **Total** | | **$5.15** |

### Scenario 3: Large Dataset (1 TB)

**Requirements:**
- 1,000 GB (1 TB) in Deep Archive
- Restore with Bulk tier
- Copy to target account (same region)
- Keep in Glacier Instant Retrieval

**Cost Breakdown:**

| Item | Calculation | Cost |
|------|-------------|------|
| Deep Archive storage (1 month) | 1,000 GB × $0.00099 | $0.99 |
| Bulk restore | 1,000 GB × $0.025 | $25.00 |
| Restore requests | ~100 files × $0.10 / 1,000 | $0.01 |
| Data transfer (same region) | 1,000 GB × $0 | $0.00 |
| Target Glacier IR (1 month) | 1,000 GB × $0.004 | $4.00 |
| Copy requests | 100 × $0.005 / 1,000 | $0.00 |
| **Total** | | **$30.00** |

### Scenario 4: Cross-Region Transfer (100 GB)

**Requirements:**
- 100 GB in Deep Archive (us-east-1)
- Restore with Bulk tier
- Copy to target account (ap-northeast-2)
- Keep in Standard storage

**Cost Breakdown:**

| Item | Calculation | Cost |
|------|-------------|------|
| Deep Archive storage (1 month) | 100 GB × $0.00099 | $0.10 |
| Bulk restore | 100 GB × $0.025 | $2.50 |
| Data transfer (cross-region) | 100 GB × $0.02 | $2.00 |
| Target Standard storage (1 month) | 100 GB × $0.023 | $2.30 |
| **Total** | | **$6.90** |

## Cost Optimization Strategies

### 1. Choose the Right Restore Tier

**Bulk vs Standard:**
```
100 GB Bulk:     $2.50
100 GB Standard: $10.00
Savings: $7.50 (75%)
```

**Recommendation:** Use Bulk unless you need immediate access.

### 2. Same Region Transfer

**Cost Comparison (100 GB):**
```
Same region:  $0
Cross-region: $2.00
Savings: $2.00 (100%)
```

**Recommendation:** Deploy target bucket in the same region when possible.

### 3. Optimize Target Storage Class

**Monthly Storage Cost (100 GB):**
```
Standard:               $2.30
Intelligent-Tiering:    $2.55 (includes monitoring)
Glacier IR:             $0.40
Deep Archive:           $0.10
```

**Decision Tree:**
- **Frequent access (>1/month)**: Standard or Intelligent-Tiering
- **Quarterly access**: Glacier Instant Retrieval
- **Annual access**: Glacier Flexible Retrieval
- **Archival**: Deep Archive

### 4. Minimize Restore Duration

**Restore Duration Impact (100 GB, 7 days):**
```
Restored data counts as additional storage:
100 GB × $0.023 × (7/30) = $0.54

Recommendation: Keep restore days to minimum needed
```

### 5. Batch Transfers

**Request Cost Optimization:**
```
1,000 small files (1 GB each):
- PUT requests: 1,000 × $0.005 / 1,000 = $0.005
- Restore requests: 1,000 × $0.10 / 1,000 = $0.10

100 large files (10 GB each):
- PUT requests: 100 × $0.005 / 1,000 = $0.0005
- Restore requests: 100 × $0.10 / 1,000 = $0.01

Savings: ~90% on requests
```

**Recommendation:** Archive larger files when possible.

### 6. Early Deletion Consideration

**180-Day Minimum:**

If you delete a Deep Archive object before 180 days, you're charged for the remaining time.

**Example:**
```
100 GB stored for 30 days, then deleted:
- Actual storage: 30 days × $0.00099 = $0.03
- Early deletion charge: 150 days × $0.00099 = $0.15
- Total: $0.18
```

**Recommendation:** Only use Deep Archive for long-term storage (180+ days).

## Monthly Cost Calculator

### Formula

```
Total Cost = Storage Cost + Restore Cost + Transfer Cost + Target Storage Cost

Where:
- Storage Cost = Data Size (GB) × $0.00099 × Months
- Restore Cost = Data Size (GB) × $0.025 (Bulk) or $0.10 (Standard)
- Transfer Cost = Data Size (GB) × $0 (same region) or $0.02 (cross-region)
- Target Storage Cost = Data Size (GB) × Target Storage Rate × Months
```

### Python Calculator

```python
def calculate_cost(
    data_size_gb,
    restore_tier="Bulk",
    same_region=True,
    target_storage_class="Standard",
    months=1
):
    # Pricing
    deep_archive_rate = 0.00099
    restore_rates = {"Bulk": 0.025, "Standard": 0.10}
    transfer_rate = 0 if same_region else 0.02
    storage_rates = {
        "Standard": 0.023,
        "Intelligent-Tiering": 0.0255,
        "Glacier-IR": 0.004,
        "Deep-Archive": 0.00099
    }

    # Calculate
    storage_cost = data_size_gb * deep_archive_rate * months
    restore_cost = data_size_gb * restore_rates[restore_tier]
    transfer_cost = data_size_gb * transfer_rate
    target_cost = data_size_gb * storage_rates[target_storage_class] * months

    total = storage_cost + restore_cost + transfer_cost + target_cost

    return {
        "storage": storage_cost,
        "restore": restore_cost,
        "transfer": transfer_cost,
        "target": target_cost,
        "total": total
    }

# Example usage
result = calculate_cost(100, "Bulk", True, "Standard", 1)
print(f"Total cost: ${result['total']:.2f}")
```

## Real-World Examples

### Example 1: Annual Backup Transfer

**Scenario:**
- Company stores 5 TB of annual backups in Deep Archive
- Needs to transfer to new account once per year
- Uses Bulk restore
- Same region transfer

**Annual Cost:**
```
Storage (12 months):     5,000 GB × $0.00099 × 12 = $59.40
Restore (once):          5,000 GB × $0.025 = $125.00
Transfer:                $0.00
Target storage (1 month): 5,000 GB × $0.00099 = $4.95

Total: $189.35/year
```

### Example 2: Disaster Recovery

**Scenario:**
- 500 GB disaster recovery data
- Needs immediate access (Standard tier)
- Cross-region for redundancy
- Keep in Standard for quick access

**One-Time Cost:**
```
Storage (1 month):       500 GB × $0.00099 = $0.50
Restore (Standard):      500 GB × $0.10 = $50.00
Transfer (cross-region): 500 GB × $0.02 = $10.00
Target storage (1 month): 500 GB × $0.023 = $11.50

Total: $72.00
```

## Cost Comparison: Deep Archive vs Other Solutions

### Deep Archive + Transfer vs. Alternatives (1 TB, 1 year)

| Solution | Storage | Retrieval | Transfer | Total |
|----------|---------|-----------|----------|-------|
| **Deep Archive → Standard** | $11.88 | $25.00 | $0 | $36.88 |
| **Glacier Flexible → Standard** | $43.20 | $10.00 | $0 | $53.20 |
| **Standard (no transfer)** | $276.00 | $0 | $0 | $276.00 |
| **Physical media (Snowball)** | $0 | $0 | $250 | $250 |

**Winner:** Deep Archive + Transfer (85% savings vs. Standard)

## Monitoring Costs

### AWS Cost Explorer

Filter by:
- Service: Amazon S3
- Usage Type:
  - `DataTransfer-In-Bytes`
  - `DataTransfer-Out-Bytes`
  - `Requests-Tier1` (PUT, COPY)
  - `Requests-Tier2` (GET)
  - `Restore-Requests`

### Cost Alerts

Set up billing alerts in CloudWatch:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name s3-transfer-cost-alert \
    --alarm-description "Alert if S3 costs exceed $100" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 21600 \
    --evaluation-periods 1 \
    --threshold 100 \
    --comparison-operator GreaterThanThreshold
```

## Summary

### Key Takeaways

1. **Deep Archive is cheapest for long-term storage** (180+ days)
2. **Bulk restore saves 75%** vs. Standard tier
3. **Same-region transfers are free**
4. **Choose target storage class based on access patterns**
5. **Batch files to reduce request costs**
6. **Monitor costs with AWS Cost Explorer**

### Quick Reference

**Typical Costs (100 GB, same region):**
- **Minimum**: ~$3 (Bulk + Glacier IR target)
- **Recommended**: ~$5 (Bulk + Intelligent-Tiering)
- **Maximum**: ~$12 (Standard + Standard target)

### Cost Estimation Tool

Use AWS Pricing Calculator:
https://calculator.aws/#/addService/S3

Or use the provided Python script for quick estimates.

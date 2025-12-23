# Healthcare Data Quality Framework

## 📋 Overview

**Business Problem:** Healthcare organizations manage patient care using data from multiple disconnected systems—Claims, HIE, and Authorizations. Data gaps create blind spots in care coordination and revenue leakage.

**Solution:** Comprehensive framework measuring capture rates across systems, categorizing match types, and identifying geographic patterns.

**Impact:** Identified 37% of events missing claims data; discovered Texas offices had 35-43% HIE capture vs. 80-97% in Virginia.

---

## 🛠️ Technologies

- SQL (Databricks)
- HTML/CSS for executive summaries

---

## 📊 Key Features

1. **Multi-Source Match Analysis** - Categorizes events by capture source
2. **Signal-to-Noise Metrics** - Coverage and false positive rates
3. **Geographic Comparison** - Regional performance patterns
4. **Authorization Noise Detection** - Identifies orphaned authorizations

---

## 🔧 Technical Highlights

### Match Type Categorization
```sql
CASE 
    WHEN claim_id IS NOT NULL AND hie_id IS NOT NULL THEN 'full-match'
    WHEN claim_id IS NOT NULL THEN 'claims-auth'
    WHEN hie_id IS NOT NULL THEN 'hie-auth'
    ELSE 'auth-only (NOISE)'
END AS match_type
```

### Hierarchical Aggregations
```sql
GROUP BY GROUPING SETS (
    (office_name, match_type),
    (office_name),
    ()
)
```

---

## 📁 Files

| File | Description |
|------|-------------|
| `sql/data_completeness_analysis.sql` | Main analysis query |

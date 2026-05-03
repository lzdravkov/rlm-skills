# GUID Strategy — Patterns and Scripts

## Why GUIDs Are Required

Salesforce record IDs are org-specific. The same product in DEV, SIT, and PROD has three different Salesforce IDs. Without a custom GUID field, you cannot reliably upsert records across orgs — you'll create duplicates or corrupt data.

A GUID field provides a single, immutable, globally unique identifier that travels with the record across every org in your DevOps pipeline.

---

## Good vs. Poor GUID Design

| Characteristic | Good | Bad |
|---|---|---|
| Immutability | UUID v4 (never changes) | Record Name (user can edit) |
| Uniqueness | Globally unique across all orgs | Unique only within one org |
| Format | Single field | Concatenated (Name + Version) |
| Generation | Programmatic (code) | Manual (user types it) |
| Translatable | No | Yes (conditional keys break across locales) |

**Good example**: `a1b2c3d4-e5f6-7890-abcd-ef1234567890` (UUID v4)
**Bad example**: `FESBA-1500-v2-Enterprise` (mutable, composite)

---

## Creating a GUID Field (UI Steps)

1. Setup → Object Manager → select object
2. Fields & Relationships → New
3. Field Type: **Text**, Length: **255**
4. Field Label: `GUID`, Field Name: `GUID`
5. Check: **Unique** ✅ and **External ID** ✅
6. Field-level security: grant Read/Edit to all deployment profiles
7. Repeat for every object in your deployment plan

**Note**: Non-extensible objects (cannot add fields) — use an external reference table:
```
GUID_Reference__c (custom object)
  ├── GUID__c (Text 255, Unique, ExternalID)
  ├── SalesforceId__c (Text 18)
  ├── ObjectApiName__c (Text 100)
  └── Environment__c (Text 50) — DEV | SIT | UAT | PROD
```

---

## Creating a GUID Field (Metadata API)

`force-app/main/default/objects/Product2/fields/GUID__c.field-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>GUID__c</fullName>
    <externalId>true</externalId>
    <label>GUID</label>
    <length>255</length>
    <required>false</required>
    <trackHistory>false</trackHistory>
    <type>Text</type>
    <unique>true</unique>
</CustomField>
```

---

## Backfilling GUIDs on Existing Records

Run this script in the source org before first deployment:

```apex
// Backfill GUID__c on Product2 records that don't have one
List<Product2> products = [
    SELECT Id, GUID__c FROM Product2 WHERE GUID__c = null
];
for (Product2 p : products) {
    p.GUID__c = generateUUID();
}
update products;

// UUID v4 generator (Apex)
public static String generateUUID() {
    Blob b = Crypto.generateAesKey(128);
    String h = EncodingUtil.convertToHex(b);
    return h.substring(0,8)  + '-' +
           h.substring(8,12)  + '-' +
           '4' + h.substring(13,16) + '-' +
           toVariant(h.substring(16,17)) + h.substring(17,20) + '-' +
           h.substring(20,32);
}
private static String toVariant(String hex) {
    Integer i = Integer.valueOf('0x' + hex);
    return EncodingUtil.convertToHex(Blob.valueOf(String.valueOf((i & 0x3) | 0x8)));
}
```

---

## Upsert Using GUID (Salesforce CLI)

```bash
# Upsert Product2 records using GUID__c as external ID
sf data upsert bulk \
  --sobject Product2 \
  --file products.csv \
  --external-id GUID__c \
  --target-org <targetAlias> \
  --wait 10

# products.csv must include GUID__c column
# Name,ProductCode,IsActive,GUID__c
# "FESBA 1500kW","FESBA-1500",true,"a1b2c3d4-..."
```

---

## GUID in Deployment Cycle

1. **Source org**: Generate GUIDs for all records (backfill script above)
2. **Export**: Include GUID__c in all CSV/JSON exports
3. **Target org**: Ensure GUID field exists before loading
4. **Upsert**: Use `--external-id GUID__c` — creates new record if GUID not found, updates if found
5. **Verification**: After upsert, compare record counts between orgs

---

## Non-Extensible Objects

Some Revenue Cloud objects cannot have custom fields added. For these, maintain an external mapping table using `GUID_Reference__c` (see above) or use the object's existing unique API Name field where one exists (e.g., metadata types use DeveloperName as the natural key).

# Constraint Modeling Language (CML) — Patterns and Examples

CML is Revenue Cloud's declarative rule language for expressing product configuration constraints without Apex code. Rules are stored in `ProductConfigurationRule` records and evaluated at runtime by the configurator engine.

Source: RLM Developer Guide v66.0, Chapter 7, p. 993–1111.

---

## Core CML Concepts

### Requires
If attribute A has value X, then attribute B must have value Y.
```cml
REQUIRES
  IF DutyRating == "Standby (STB)"
  THEN Enclosure IN ["Open Skid", "Sound Attenuated"]
```

### Excludes
Attribute A = X is incompatible with attribute B = Y.
```cml
EXCLUDES
  DutyRating == "Data Center Continuous (DCC)"
  AND Enclosure == "Open Skid"
```

### Range Constraints
A Number attribute must fall within a min/max range.
```cml
RANGE
  requiredKW BETWEEN 100 AND 3000
```

### Default Values
Set a default value for an attribute when another condition is met.
```cml
DEFAULT
  IF ProductType == "FuelCell"
  THEN Voltage = "480V"
```

### Visibility
Show or hide an attribute based on context.
```cml
VISIBLE
  IF DutyRating != NULL
  THEN requiredKW
```

---

## Example: Generator Set Constraints

```cml
-- Rule 1: DCC duty requires indoor or sound-attenuated enclosure
EXCLUDES
  DutyRating == "Data Center Continuous (DCC)"
  AND Enclosure IN ["Open Skid", "Weather Protective"]

-- Rule 2: kW range validation
RANGE
  requiredKW BETWEEN 100 AND 3000

-- Rule 3: Default voltage for fuel cell products
DEFAULT
  IF ProductClassification.DeveloperName == "FuelCell"
  THEN Voltage = "208V"

-- Rule 4: Prime duty locks to specific cooling option
REQUIRES
  IF DutyRating == "Prime (PRP)"
  THEN CoolingType IN ["Radiator Cooled", "Remote Radiator"]
```

---

## CML Deployment

1. Author CML rule text in `ProductConfigurationRule.RuleExpression`
2. Create `ProductConfigFlowAssignment` to link rule to a product/classification
3. Activate the associated `ProductConfigurationFlow`
4. Test via `Run Config Rules Action` invocable before enabling in production

---

## Common CML Errors

| Error | Cause | Fix |
|---|---|---|
| "Unknown attribute name" | DeveloperName doesn't match AttributeDefinition | Verify exact DeveloperName spelling |
| "Rule evaluation failed" | Syntax error in REQUIRES/EXCLUDES block | Check CML syntax, especially quotes around string values |
| "Configuration flow not found" | ProductConfigFlowAssignment missing | Create assignment linking product + flow |
| Rule not triggering | Flow not activated | Activate the ProductConfigurationFlow |

---

## Best Practices

- Keep rules simple and single-purpose — one concern per rule
- Test REQUIRES before EXCLUDES (positive constraints first)
- Use `VISIBLE` to reduce cognitive load on users (hide irrelevant attributes)
- Always run `Run Config Rules Action` in a test environment before deploying to production
- Document the business reason for each rule in `ProductConfigurationRule.Description`

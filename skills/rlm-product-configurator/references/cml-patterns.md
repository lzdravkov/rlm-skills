# Constraint Modeling Language (CML) — Patterns and Examples

CML is Revenue Cloud's declarative rule language for expressing product configuration constraints without Apex code. Rules are stored in `ProductConfigurationRule` records and evaluated at runtime by the Constraint Rules Engine.

Source: RLM Developer Guide (v68.0, Winter '27) — Chapter 7: Product Configurator › Constraint Modeling Language (CML) › Core Concepts, Core Concept Examples.

> **Corrected for v68:** earlier revisions of this file documented an uppercase block-keyword
> syntax (`REQUIRES`/`IF...THEN`, `EXCLUDES`, `RANGE...BETWEEN...AND`, `DEFAULT`, `VISIBLE`).
> That syntax does not appear anywhere in the v68 guide. Real CML is authored as `type`/
> `relation` declarations (with variable domains such as `int requiredKW = [100..3000];`)
> plus lowercase, function-call-style rule statements (`constraint()`, `require()`,
> `exclude()`, `setdefault()`, `preference()`, `message()`, `rule()`, `recommend`). The examples
> below have been rewritten to match the documented syntax.

---

## Core CML Concepts

CML models are built from `type` declarations (the product/attribute structure) and `relation`
declarations (parent-child associations), with rule statements written as function calls inside
a `type` block. All examples below are adapted from the guide's Generator Set model.

### Require
Forces a component (or attribute state) into a relationship when a condition is met. `require()`
enforces physical presence — it will add the required product/value if it's missing.
```cml
type GeneratorSet {
    int requiredKW = [101..10000];
    relation enclosures : Enclosure[0..1];
    // If required power exceeds 1500 kW, a Reinforced Enclosure must be present.
    require(requiredKW > 1500, enclosures[ReinforcedEnclosure] == 1,
        "High power generator sets require a Reinforced Enclosure.");
}
type Enclosure;
type ReinforcedEnclosure : Enclosure;
```

### Exclude
Automatically removes a type from a relationship if a condition is true. `exclude()` is the one
rule type where the engine is allowed to override a user's prior selection — all other rules
(including `require()`) surface an error instead of silently changing a user's input.
```cml
type GeneratorSet {
    string DutyRating = ["Prime Power (PRP)", "Continuous Power (COP)",
        "Emergency Standby Power (ESP)"];
    relation enclosures : Enclosure[0..1];
    // Data Center Continuous duty excludes an open-skid enclosure.
    exclude(DutyRating == "Continuous Power (COP)", enclosures[OpenSkidEnclosure]);
}
type Enclosure;
type OpenSkidEnclosure : Enclosure;
```

### Range (variable domain)
A Number attribute's valid range is declared as the variable's domain — there's no separate
`RANGE` block. `constraint()` can add cross-attribute validation on top of the domain.
```cml
type GeneratorSet {
    int requiredKW = [100..3000];   // declares the valid domain directly
}
```

### Setdefault (default values)
Sets a default value/selection when a condition is met; unlike `require()`, the solver reverts
the change if the triggering condition later becomes false.
```cml
type GeneratorSet {
    string ProductClassificationName;
    string Voltage = ["208V", "480V"];
    setdefault(ProductClassificationName == "FuelCell", Voltage == "208V",
        "Defaulting Voltage to 208V for FuelCell classification.");
}
```

### Constraint (validation / "visibility"-style logic)
CML has no dedicated `VISIBLE` rule type. Use `constraint()` to enforce logical consistency
between attributes (for example, requiring one attribute to be set before another is usable).
```cml
type GeneratorSet {
    string DutyRating;
    int requiredKW = [101..10000];
    // requiredKW is only meaningful once DutyRating has been chosen.
    constraint(requiredKW > 0 -> DutyRating != null,
        "Select a Duty Rating before specifying required kW.");
}
```

---

## Example: Generator Set Constraints

```cml
type GeneratorSet {
    string DutyRating = ["Prime Power (PRP)", "Continuous Power (COP)",
        "Data Center Continuous (DCC)", "Emergency Standby Power (ESP)"];
    int requiredKW = [100..3000];   // Rule 2: kW range enforced via the variable domain
    string ProductClassificationName;
    string Voltage = ["208V", "480V"];
    string CoolingType = ["Radiator Cooled", "Remote Radiator", "None"];
    relation enclosures : Enclosure[0..1];

    // Rule 1: DCC duty excludes an open-skid or weather-protective enclosure
    exclude(DutyRating == "Data Center Continuous (DCC)", enclosures[OpenSkidEnclosure]);
    exclude(DutyRating == "Data Center Continuous (DCC)", enclosures[WeatherProtectiveEnclosure]);

    // Rule 3: Default voltage for fuel cell products
    setdefault(ProductClassificationName == "FuelCell", Voltage == "208V",
        "Defaulting Voltage to 208V for FuelCell classification.");

    // Rule 4: Prime duty requires a radiator-based cooling option.
    // Note: constraint() (not require()) is correct here — this validates an attribute
    // condition, not the physical presence of a component. See "Require Rule vs Constraint"
    // in the Core Concepts chapter.
    constraint(DutyRating == "Prime Power (PRP)" ->
        (CoolingType == "Radiator Cooled" || CoolingType == "Remote Radiator"),
        "Prime Power duty rating requires a radiator-based cooling option.");
}
type Enclosure;
type OpenSkidEnclosure : Enclosure;
type WeatherProtectiveEnclosure : Enclosure;
```

---

## CML Deployment

1. Author CML rule text in `ProductConfigurationRule.ConfigurationRuleDefinition` (textarea
   field — confirmed against v68 Ch.7 Standard Objects, printed p.962; the field is **not**
   named `RuleExpression`, which does not appear on this object in the v68 guide)
2. Create `ProductConfigFlowAssignment` to link rule to a product/classification
3. Activate the associated `ProductConfigurationFlow`
4. Test via `Run Config Rules Action` invocable before enabling in production

---

## Common CML Errors

| Error | Cause | Fix |
|---|---|---|
| "Unknown attribute name" | DeveloperName doesn't match AttributeDefinition | Verify exact DeveloperName spelling |
| "Rule evaluation failed" | Syntax error in a `constraint()`/`require()`/`exclude()` statement | Check CML syntax — parentheses, quoted string literals, and correct use of `->`, `&&`, `\|\|` |
| "Configuration flow not found" | ProductConfigFlowAssignment missing | Create assignment linking product + flow |
| Rule not triggering | Flow not activated | Activate the ProductConfigurationFlow |
| Model save fails with "type not declared" | A relation references a type that isn't explicitly declared, and `skipTypeGeneration` is set to `"true"` | Declare every type your CML references, or remove `skipTypeGeneration` |

---

## Best Practices

- Keep rules simple and single-purpose — one concern per rule
- Prefer `constraint()` for logical/attribute-level validation and `require()` only when a
  component's physical presence must be enforced (see "Require Rule vs Constraint" in the
  guide's Core Concepts chapter) — the engine will not silently override user input for either,
  except via `exclude()`
- Specify the smallest necessary cardinality range (e.g., `[0..5]` not the `[0..9999]` default)
  to reduce combinations the constraint engine must test
- Always run `Run Config Rules Action` in a test environment before deploying to production
- Document the business reason for each rule in `ProductConfigurationRule.Description`

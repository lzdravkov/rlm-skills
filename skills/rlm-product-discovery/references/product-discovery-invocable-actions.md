# Product Discovery — Standard Invocable Actions

Standard invocable actions for Product Discovery are available in Flows and Apex.
They call the same underlying CPQ composite APIs but are usable without HTTP callouts.

---

## Available Actions

*Corrected (v68 re-baseline, 2026-09-11):* the action labels below were verified against the v68
Revenue Management Developer Guide, Ch.4 › Product Catalog Management › Product Discovery ›
**Product Discovery Standard Invocable Actions** (printed pp.410–512). The v66-era table in this
file used non-standard labels (e.g. "Get Product Catalogs", "Guided Selection", "Run Qualification")
that do not match the documented action names, and it was missing two actions entirely
(**Get Catalog Details Action** and **Get Product Recommendations Action**, the latter a newer
capability backed by the Constraint Rule Engine). The corrected, complete list of 11 actions:

| Action Label | Category | Description |
|---|---|---|
| Find Products Action | Product Discovery | Searches for products from a catalog, category, or subcategory using a search term. Available API v62.0+ |
| Get Catalogs Action | Product Discovery | Returns a list of product catalogs |
| Get Catalog Details Action | Product Discovery | Returns details of a specific catalog |
| Get Categories Action | Product Discovery | Returns categories and subcategories of a catalog |
| Get Category Details Action | Product Discovery | Returns details of a specific category |
| Get Products Action | Product Discovery | Returns a list of products for a catalog/category |
| Get Product Details Action | Product Discovery | Returns full product details (attributes, hierarchy, cardinality) |
| Get Multiple Product Details Action | Product Discovery | Returns details for multiple product IDs in one call |
| Search Product with Guided Selection Action | Product Discovery | Returns products based on guided-selection search terms |
| Get Product Recommendations Action | Product Discovery | Returns recommended products for a context, using the Constraint Rule Engine |
| Execute Qualification Procedure Action | Product Discovery | Runs a qualification procedure on a list of product IDs. Available API v64.0+ |

---

## Usage in Flow

Each action is available as a **Salesforce-provided Action** element in Flow Builder under the **Product Discovery** category.

Inputs map directly to the corresponding Business API request body fields. Outputs map to the response body fields.

---

## Usage from Apex

*Corrected (v68 re-baseline):* the v66-era example below (`Flow.Interview.createInterview(...)`)
does not match the documented v68 pattern. Standard Invocable Actions are invoked from Apex via the
`Invocable.Action` class — `createStandardAction(actionName)`, then `setInvocationParameter(...)` for
each input, then `.invoke()`, then read outputs off `Invocable.Action.Result.getOutputParameters()`.
This is the pattern shown for the Find Products Action example in the v68 guide (Ch.4 › Product
Discovery Standard Invocable Actions, printed p.417):

```apex
// Example: invoke the Find Products Action from Apex
Invocable.Action action = Invocable.Action.createStandardAction('findProducts');

action.setInvocationParameter('searchTerm', 'FESBA');
action.setInvocationParameter('catalogId', '0ZSxx...');
action.setInvocationParameter('priceBookId', '01sxx...');

List<Invocable.Action.Result> results = action.invoke();

for (Invocable.Action.Result result : results) {
    if (result.isSuccess()) {
        Map<String, Object> outputs = result.getOutputParameters();
        // outputs contains the same fields as the /connect/cpq/ REST response
    }
}
```

---

## Critical Note: Agentforce / Agent Context

`getSessionId()` returns `null` in the Agentforce execution context. You cannot use `getSessionId()` to construct HTTP callouts to the `/connect/cpq/` REST endpoints from within GenAiFunction-invoked Apex.

**Workaround options:**
1. Use **SOQL directly** against `Product2`, `ProductClassificationAttr`, `AttributePicklistValue` etc. (proven pattern in this project — see `rlm-product-configurator` skill for `ProductAttributeService` implementation)
2. Use **Standard Invocable Actions** via Flow — these do not require a session ID

---

## Apex Reference (runtime_industries_cpq namespace)

*Corrected (v68 re-baseline, 2026-09-11):* the `ConnectApi.ProductDiscovery` class shown in earlier
versions of this file (with static methods `getCatalogs`/`getProducts`/`getProductDetails`/
`searchProducts`) was **not found** in the v68 Product Discovery Apex Reference (Ch.4, printed
pp.513–657) and is not a documented v68 class. There is no `ConnectApi.ProductDiscovery` service
façade with one-to-one REST-endpoint methods.

The real, documented Apex surface for Product Discovery is the **`runtime_industries_cpq`**
namespace, which exposes data wrapper (Representation/Input) classes used with Apex-defined Flow
variables and with the `Invocable.Action` pattern shown above — not a set of directly callable
static service methods. Representative classes (Ch.4 › Product Discovery Apex Reference, printed
pp.513–546) include:

- `runtime_industries_cpq.CatalogOutputRepresentation`, `CategoryOutputRepresentation`
- `runtime_industries_cpq.ProductOutputRepresentation`, `ProductDetailsRepresentation`, `ProductListRepresentation`
- `runtime_industries_cpq.BulkProductDetailsInputBody`, `BulkProductDetailsRepresentation`
- `runtime_industries_cpq.SearchProductsRepresentation`, `SearchProductsFacetRepresentation`
- `runtime_industries_cpq.GuidedSelectionRepresentation`, `GuidedSelectionSearchTerm`, `GuidedSelectionSearchTermList`
- `runtime_industries_cpq.QocQualificationOutputRepresentation`, `QualificationContextOutputRepresentation`
- `runtime_industries_cpq.FilterInputRepresentation`, `FilterCriteriaInputRepresentation`, `RelatedObjectFilterInputRepresentation`
- `runtime_industries_cpq.ProductRecommendationRule`, `ConfigRuleResult` (backs Get Product Recommendations Action)

A small number of shared/user-context types live directly under `ConnectApi` rather than
`runtime_industries_cpq` — e.g. `ConnectApi.UserContextInputRepresentation`,
`ConnectApi.UserContextRepresentation`, and `ConnectApi.CpqMessageOutputRepresentation` — but these
are supporting input/message types, not a `ProductDiscovery` service class. If your org exposes a
`ConnectApi.ProductDiscovery` class not reflected here, treat that as newer/org-specific and verify
directly against the Apex Reference before relying on it — this section is annotated as corrected,
not exhaustively verified against every page of the 145-page Apex Reference section.

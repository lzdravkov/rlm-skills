# Product Discovery — Standard Invocable Actions

Standard invocable actions for Product Discovery are available in Flows and Apex.
They call the same underlying CPQ composite APIs but are usable without HTTP callouts.

---

## Available Actions

| Action Label | Category | Description |
|---|---|---|
| Get Product Catalogs | Product Discovery | Returns a list of product catalogs |
| Get Product Categories | Product Discovery | Returns categories and subcategories of a catalog |
| Get Product Category Details | Product Discovery | Returns details of a specific category |
| Get Product Details | Product Discovery | Returns full product details (attributes, hierarchy, cardinality) |
| Get Products | Product Discovery | Returns a list of products for a catalog/category |
| Get Bulk Products | Product Discovery | Returns details for multiple product IDs |
| Search Products | Product Discovery | Returns products matching a search query or term |
| Guided Selection | Product Discovery | Returns products based on guided selection search terms |
| Run Qualification | Product Discovery | Runs a qualification procedure on a list of product IDs |

---

## Usage in Flow

Each action is available as a **Salesforce-provided Action** element in Flow Builder under the **Product Discovery** category.

Inputs map directly to the corresponding Business API request body fields. Outputs map to the response body fields.

---

## Usage from Apex

```apex
// Example: search products via invocable action from Apex
Map<String, Object> inputs = new Map<String, Object>{
    'searchTerm' => 'FESBA',
    'catalogId'  => '0ZSxx...',
    'priceBookId' => '01sxx...',
    'userContext' => new Map<String, Object>{
        'accountId' => '001xx...'
    }
};

List<Map<String, Object>> results = (List<Map<String, Object>>)
    Flow.Interview.createInterview('SearchProducts', inputs);
```

---

## Critical Note: Agentforce / Agent Context

`getSessionId()` returns `null` in the Agentforce execution context. You cannot use `getSessionId()` to construct HTTP callouts to the `/connect/cpq/` REST endpoints from within GenAiFunction-invoked Apex.

**Workaround options:**
1. Use **SOQL directly** against `Product2`, `ProductClassificationAttr`, `AttributePicklistValue` etc. (proven pattern in this project — see `rlm-product-configurator` skill for `ProductAttributeService` implementation)
2. Use **Standard Invocable Actions** via Flow — these do not require a session ID

---

## Apex Reference (ConnectApi namespace)

Product Discovery APIs are also available through the `ConnectApi` Apex namespace for server-side use:

```apex
// Catalog list
ConnectApi.CpqOutputRepresentation result =
    ConnectApi.ProductDiscovery.getCatalogs(correlationId, userContextInput, limit, offset, orderBy);

// Products list
ConnectApi.CpqOutputRepresentation products =
    ConnectApi.ProductDiscovery.getProducts(
        catalogId, categoryId, priceBookId, correlationId,
        enablePricing, enableQualification, limit, cursor, userContextInput);

// Product details
ConnectApi.CpqOutputRepresentation details =
    ConnectApi.ProductDiscovery.getProductDetails(productId, requestInput);

// Search
ConnectApi.CpqOutputRepresentation searchResult =
    ConnectApi.ProductDiscovery.searchProducts(searchRequestInput);
```

The `ConnectApi.ProductDiscovery` methods correspond 1:1 with the REST endpoints.

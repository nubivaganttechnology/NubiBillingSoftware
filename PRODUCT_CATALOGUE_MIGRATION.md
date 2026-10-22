# Dynamic product catalogue

The form loads SYSTEM and BUSINESS master data, attribute definitions, options and subcategory templates exclusively through scoped Firestore REST queries. No bundled catalogue or release-based fallback exists. Central administrators manage SYSTEM records directly in Firestore; release records may remain for version tracking but do not gate client reads.

Master values merge by ID, with current-business records overriding matching SYSTEM IDs. Subcategories retain categoryId filtering. Templates merge by attributeId and sortOrder; PRODUCT and VARIANT levels render separately. BUSINESS templates can suppress an inherited attribute using an INACTIVE row. A custom subcategory starts with an empty template and can use Add Business Attribute.

Collections: `product_attributes`, `product_attribute_options`, `subcategory_attribute_templates`. Definitions support TEXT, NUMBER, SELECT, MULTI_SELECT and BOOLEAN. Template fields include required/defaultValue/attributeLevel/sortOrder. Options merge SYSTEM and current-business ACTIVE options. Empty master data displays an unavailable-catalogue message; no local defaults are restored.

## Existing data and sequences

No historical product, purchase or inventory documents are rewritten. Fixed fields remain readable and map into attributeValues. Missing SKU conversions default to 1:1. New records store structured attributeValues and conversion metadata; they contain no purchase quantities, transaction rates, suppliers or stock locations.

Product/SKU counters use `${tenantId}_${businessId}_PRODUCT` and `${tenantId}_${businessId}_PRODUCT_VARIANT` in document_sequences. Both ranges and the product uniqueness reservation commit atomically with creation. New businesses initialize at 1. Existing businesses with generated codes but missing counters require an administrator to initialize nextNumber from an audited migration before entry is allowed. Runtime generation never derives a counter from the last product and never changes existing codes.

Legacy documents missing tenantId require an administrator to backfill verified ownership before isolated queries can include them. Never infer tenant ownership from a client-supplied business ID.

## Deployment authorization contract

This repository does not contain the deployed Firestore security rules. Integrate the new collections into those existing rules before deployment: SYSTEM reads must be allowed for authorized users; SYSTEM writes must require central administrators. BUSINESS reads/writes must validate membership in both tenantId and businessId, enforce immutable ownership, and authorize product_master.create/update/deactivate as appropriate. Product and sequence writes require product.create and immutable codes. Uniqueness documents and sequence counters must participate in the same authorized atomic creation. Deny cross-business changes and physical deletion of referenced masters. Client permission checks are not a replacement for REST security rules.

Equality-only queries use Firestore index merging; if the deployed database reports an index requirement, provision the returned index without weakening scope filters.

## Verification

`flutter test` covers Firestore scope and parent filtering, dynamic templates and options, empty catalogue behavior, custom masters and commercial unit conversion. `flutter analyze` also checks the implementation; unrelated existing repository diagnostics remain.

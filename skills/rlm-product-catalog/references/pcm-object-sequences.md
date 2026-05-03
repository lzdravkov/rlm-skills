# Product Catalog Management — Full Object Deployment Sequence

Deploy configuration data in this exact order. Violating the sequence causes INVALID_CROSS_REFERENCE_KEY errors.

Source: RLM Developer Guide v66.0, Chapter 3, p. 20–22.

| Seq | Object Name | API Name | Lookup Fields (Foreign Keys) |
|---|---|---|---|
| 1 | Product Specification Type | ProductSpecificationType | User |
| 2 | Product Specification Record Type | ProductSpecificationRecordType | Product Specification Type |
| 3 | Attribute Picklist | AttributePicklist | User, User Group, Unit of Measure |
| 4 | Attribute Picklist Value | AttributePicklistValue | User, AttributePicklist (Master-Detail) |
| 5 | Unit of Measure Class | UnitOfMeasureClass | User, Unit of Measure |
| 6 | Unit of Measure | UnitOfMeasure | User Group, Unit of Measure Class |
| 7 | Attribute Definition | AttributeDefinition | User, AttributePicklist, Unit of Measure |
| 8 | Attribute Category | AttributeCategory | User Group |
| 9 | Attribute Category Attribute | AttributeCategoryAttribute | User Group, AttributeCategory, AttributeDefinition |
| 10 | Product Classification | ProductClassification | User, User Group, Product Classification |
| 11 | Product Classification Attribute | ProductClassificationAttr | AttributeDefinition, AttributeCategory, ProductClassificationAttribute, ProductClassification, User, User Group, Unit of Measure |
| 12 | Tax Policy | TaxPolicy | User, Tax Treatment |
| 13 | Product | Product2 | ProductClassification, BillingPolicy, User, ExternalDataSource, TaxPolicy, Unit of Measure |
| 14 | Tax Engine | TaxEngine | NamedCredential, Tax Engine Provider |
| 15 | Tax Treatment | TaxTreatment | LegalEntity, Product2, TaxPolicy, TaxEngine |
| 16 | Product Attribute Definition | ProductAttributeDefinition | AttributeDefinition, AttributeCategory, User, ProductAttributeDefinition, ProductClassificationAttr, Unit of Measure |
| 17 | Attribute Picklist Excluded Value | AttrPicklistExcludedValue | ProductClassificationAttr, ProductAttributeDefinition, AttributePicklistValue |
| 18 | Product Attribute Scope | ProdtAttrScope | User, User Group |
| 19 | Product Attribute Mapped Scope | ProdtAttrMappedScope | ProductClassificationAttr, ProductAttributeDefinition, ProdtAttrMappedScope, ProdtAttrScope |
| 20 | Product Selling Model | ProductSellingModel | User |
| 21 | Product Selling Model Option | ProductSellingModelOption | User, ProductSellingModel, ProrationPolicy |
| 22 | Product Ramp Segment | ProductRampSegment | User, ProductSellingModel, Product2 |
| 23 | Product Relationship Type | ProductRelationshipType | User |
| 24 | Product Component Group | ProductComponentGroup | User, User Group, ProductComponentGroup |
| 25 | Product Related Component | ProductRelatedComponent | User, Product2, ProductClassification, ProductSellingModel, ProductComponentGroup, ProductRelationshipType, Unit of Measure |
| 26 | Product Related Group Override | ProductComponentGrpOverride | User, User Group, Product2, ProductComponentGroup |
| 27 | Product Related Component Override | ProductRelComponentOverride | UserGroup, Product2, ProductRelatedComponent, Unit of Measure |
| 28 | Catalog | ProductCatalog | User, User Group |
| 29 | Category | ProductCategory | User, Catalog (Master-Detail) |
| 30 | Product Category Product | ProductCategoryProduct | Product2, Category (Master-Detail) |
| 31 | Product Qualification | ProductQualification | User, User Group, Product2 |
| 32 | Product Disqualification | ProductDisqualification | User, User Group, Product2 |
| 33 | Product Category Qualification | ProductCategoryQualification | User, User Group, Category |
| 34 | Product Category Disqualification | ProductCategoryDisqual | User, User Group, Category |
| 35 | Runtime Catalog Index Settings | RuntimeCatalogIndexSetting | (internal) |
| 36 | WebStore Search Attr Settings | WebStoreSearchAttrSettings | (internal) |
| 37 | Assessment Question | AssessmentQuestion | AssessmentQuestionVersion, User, User Group |
| 38 | Assessment Question Version | AssessmentQuestionVersion | AssessmentQuestion (Master-Detail) |
| 39 | Assessment | Assessment | Account, Contact, User, User Group, OmniProcess |
| 40 | Assessment Question Response | AssessmentQuestionResponse | AssessmentQuestionVersion, Assessment (Master-Detail), User, User Group |
| 41 | Omni Process | OmniProcess | User, User Group |
| 42 | Omni Process Element | OmniProcessElement | OmniProcess (Master-Detail), OmniProcessElement |
| 43 | OmniProcess Assessment Question Version | OmniProcessAssmtQuestionVer | AssessmentQuestionVersion, OmniProcess, OmniProcessElement, User Group |
| 44 | Assessment Question Set | AssessmentQuestionSet | User, User Group |
| 45 | Assessment Question Assignment | AssessmentQuestionAssignment | AssessmentQuestionSet, User, User Group |

## Translation Table Objects (deploy alongside their parent)
| Parent Seq | Translation Object | API Name |
|---|---|---|
| 4 | AttributePicklistValue Data Translation | AttributePicklistValueDataTranslation |
| 7 | Attribute Definition Data Translation | AttributeDefinitionDataTranslation |
| 8 | Attribute Category Data Translation | AttributeCategoryDataTranslation |
| 10 | Product Classification Data Translation | ProductClassificationDataTranslation |
| 11 | Product Classification Attribute Data Translation | ProductClassificationAttrDataTranslation |
| 13 | Product2 Data Translation | Product2DataTranslation |
| 20 | Product Selling Model Data Translation | ProductSellingModelDataTranslation |
| 21 | Product Selling Model Option Data Translation | ProductSellingModelOptionDataTranslation |
| 28 | Product Catalog Data Translation | ProductCatalogDataTranslation |
| 29 | Product Category Data Translation | ProductCategoryDataTranslation |

## Key Rules
- Always deploy parent before child
- Circular dependencies: deploy A without B reference → deploy B → redeploy A with B reference
- Non-extensible objects (no GUID field possible): use an external reference table
- Metadata types (ProductSpecificationType, ProductSpecificationRecordType): deploy before any data

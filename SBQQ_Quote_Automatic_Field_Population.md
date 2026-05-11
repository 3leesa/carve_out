# `SBQQ__Quote__c` automatic field population

This document summarizes what is automatically set on `SBQQ__Quote__c` when a record is created or updated in this repository.

Scope:
- Focused on fields written automatically on the quote itself.
- Based on active Apex triggers/classes and active flows found in this project.
- Obsolete flows are mentioned only when they help explain legacy behavior still present in metadata.

Main automation sources reviewed:
- `CpqQuoteTrigger` + `TR003_CPQQuoteTriggerHandler`
- `TR015_TaskTriggerHandler.updateQuotesAfterEmailIsSentWithRT`
- `UniversignEventTrigger`
- Active flows:
  - `QUO003_UpdateOpptyStatusOnContratQuoteStatus`
  - `QUO011_RT_TIMER_ExpiredQuote`
  - `QUO012_UpdateQuoteB2B2C_ME`
  - `PB_AbandonedQuotesWhenSecondaryQuoteBecomePrimary`
  - quote creation flows such as `DEV_VWF006_CpqQuoteAppareilCreation` and `DEV_VWF023_CpqQuotePrestationCreation`
- Batch:
  - `AbandonOldQuotesBatch`

## 1. What is set automatically on quote creation

### 1.1 Common trigger behavior on insert

Source: `CpqQuoteTrigger` before/after insert.

#### Status
- `SBQQ__Status__c = 'Draft'`
  - Set in before insert for all quote record types except `Devis_Pieces`.
  - Exception: if `TECH_Souscription__c = 'WEB'`, the trigger does not force `Draft`.

#### Quote process
- `SBQQ__QuoteProcessId__c`
  - Automatically filled if blank, based on record type:
  - `PropositionContrat` -> `GuidedSellingProcess2Id__c`
  - `Devis_appareil` -> `GuidedSellingProcess1Id__c`
  - `Prestation_Hors_Contrat` -> `GuidedSellingProcess3Id__c`

#### Template / CGE / contract classification fields
- `Quote_Template_Id_Contrat__c`
- `TECH_SectionCGE__c`
- `TECH_FormuleLiberte__c`
  - Set by `updateTemplateId(...)`.
  - For `PropositionContrat`, values depend on:
    - `TECH_Souscription__c`
    - `FamilleTarifaire__c`
    - product code found on quote lines (`TECH_CongaProductCode__c`)
    - custom metadata `CPQ_CongaQuoteTemplate__mdt`
  - For `Prestation_Hors_Contrat` with forfait revision logic, `TECH_SectionCGE__c` and `Quote_Template_Id_Contrat__c` are also set.

#### Text cleanup
- `Description_travaux_complementaires__c`
  - Double quotes `"` are replaced by single quotes `'`.

### 1.2 When the quote is created by cloning another quote

Source: `copyAllTechFieldsOnClonedQuote(...)` and `setJuamnjiToNullOnClonedQuote(...)`.

#### Copied from source quote
- All fields listed in field set `QuoteFieldsToClone`.

#### Reset on cloned quote
- `IdentifiantExterne__c = null`
- `TECH_JumId__c = null`
- `DateDevisAccepte__c = null`
- `SignatureDate__c = null`

### 1.3 External ID generated after insert

Source: `generateExternalId(...)` called after insert.

- `IdentifiantExterne__c`
  - Generated if blank.
  - Built from quote `Name` + last 11 chars of the quote Id.

### 1.4 Values set by creation flows

These are the values explicitly assigned by creation flows before the trigger adds its own logic.

#### `DEV_VWF006_CpqQuoteAppareilCreation` (`Devis_appareil`, active)
- `Asset__c`
- `Conga_EmailReplyToId__c`
- `CpqReleveTechnique__c`
- `Dossier_Coup_de_pouce__c`
- `Estimation__c`
- `Estimation_principale__c`
- `Informations_Magasinier__c`
- `Logement__c`
- `MaPrimeRenov__c`
- `Montant_aides_deja_demande__c`
- `OpportunityCreatedByRole__c`
- `Pas_de_CEE_avec_EHS__c`
- `RecordTypeId`
- `Releve_Administratif__c`
- `SBQQ__Opportunity2__c`
- `SBQQ__PricebookId__c`
- `SBQQ__Primary__c`
- `SBQQ__SalesRep__c`
- `SurfaceDeLaPieceChauffee__c`
- `Surface_habitable_chauffee__c`
- `TECH_Consentement__c`
- `TECH_SurfaceHabitable__c`
- `TECH_UniqueFlowId__c`
- `Type_menage__c`
- `WorkOrder__c`
- `isFirstInstallation__c`

#### `DEV_VWF023_CpqQuotePrestationCreation` (`Prestation_Hors_Contrat`, active)
- `Asset__c`
- `Conga_EmailReplyToId__c`
- `FamilleTarifaire__c`
- `Logement__c`
- `RecordTypeId`
- `SBQQ__Account__c`
- `SBQQ__Opportunity2__c`
- `SBQQ__PricebookId__c`
- `SBQQ__SalesRep__c`
- `SalesRepRessource__c`
- `TECH_CodeGenerique__c`
- `TECH_Consentement__c`
- `TECH_UniqueFlowId__c`

#### `DEV_VWF005_CpqQuoteContratCreation` (`PropositionContrat`, obsolete but useful for legacy understanding)
- `Asset__c`
- `Client_demandeur__c`
- `FamilleTarifaire__c`
- `InstallDate__c`
- `RecordTypeId`
- `RemiseCommercialeKI__c`
- `SBQQ__Opportunity2__c`
- `SBQQ__Primary__c`
- `SBQQ__SalesRep__c`
- `TECH_AssetFonction__c`
- `TECH_CodeGenerique__c`
- `TECH_Duree_du_contrat__c`
- `TECH_MotifSouscriptionLitteral__c`
- `TECH_Souscription__c`
- `TECH_UniqueFlowId__c`

## 2. What is set automatically on quote update

### 2.1 Status-driven dates on non-`Devis_appareil` quotes

Source: `FillQuoteDate(...)`.

- `DateDevisEnvoye__c = TODAY()`
  - When status changes to `Presented`.
- `DateDevisAccepte__c = TODAY()`
  - When status changes to `Accepted`.

Note:
- This logic excludes `Devis_appareil`.

### 2.2 Contract quote status handling (`PropositionContrat`)

Sources:
- `setContractToPrimaryWhenAccepted(...)`
- active flow `QUO003_UpdateOpptyStatusOnContratQuoteStatus`
- `UniversignEventTrigger`

#### When a contract quote becomes accepted
- `SBQQ__Primary__c = true`
  - If record type is `PropositionContrat` and it was not primary yet.
- `DateDevisAccepte__c = TODAY()`
  - Via trigger logic on non-`Devis_appareil`.

#### When a primary contract quote has a `Conga_Contact_ID__c`
- `Primary_Contact__c = Conga_Contact_ID__c`
  - Set by `QUO003_UpdateOpptyStatusOnContratQuoteStatus`.

#### Signature session timestamps
- `Signature_DateInitSession__c = TODAY()`
- `Signature_DateTimeInitSession__c = NOW()`
  - Set by `QUO003_UpdateOpptyStatusOnContratQuoteStatus` when a new signature/pre-contractual cycle starts.
- `Signature_DateTimeInitSession__c = NOW()`
  - Also refreshed in one flow path when `EnvoiParCourrier__c = true`.

#### Contract effective dates
- `SBQQ__StartDate__c = TODAY()`
- `SBQQ__EndDate__c = calculated end date`
  - Set by `QUO003_UpdateOpptyStatusOnContratQuoteStatus`.

#### If Universign confirms signature success
- `SBQQ__Status__c = 'Accepted'`
- `Universign_Signed__c = true`
- `signatureDateUniversign__c = TODAY()`
- `SignatureDate__c = NOW()`
- `Signature_UpdateSignatureError__c = null`

#### If Universign returns an error
- `Signature_UpdateSignatureError__c = error message`

### 2.3 Device quote (`Devis_appareil`) status handling

Sources:
- `TR015_TaskTriggerHandler.updateQuotesAfterEmailIsSentWithRT(...)`
- `setPrimaryLastQuotePresented(...)`
- `QUO011_RT_TIMER_ExpiredQuote`
- `AbandonOldQuotesBatch`

#### When an email task is created on the quote
- `SBQQ__Status__c = 'Presented'`
  - For `Devis_appareil`.
- `EnvoiParCourrier__c = true`
  - If the task recipient is the printer account.
- `Envoi_par_mail__c = true`
  - Otherwise.
- `DateDevisEnvoye__c = TODAY()`
  - The code updates it when already non-null; this looks intended to behave like a refresh date.

#### When a non-estimate device quote becomes presented
- `SBQQ__Primary__c = true`
  - If all of these are true:
    - not a VT quote (`Conga_Pack__c != 'Offre Borne Electrique - Visite Technique'`)
    - not `Estimation__c`
    - not `Estimation_principale__c`
    - not already primary

#### VT special rule
- `SBQQ__Primary__c = false`
  - If `Conga_Pack__c = 'Offre Borne Electrique - Visite Technique'` and quote is primary.

#### Expiration automation for presented charging-station quotes
- `SBQQ__Status__c = 'Abandoned'`
  - Set 60 days after `DateDevisEnvoye__c`
  - Only when:
    - current status is `Presented`
    - `Type_equipement_propose__c = 'Borne de Recharge'`

#### Batch cleanup for old draft device quotes
- `SBQQ__Status__c = 'Abandoned'`
  - Applied by `AbandonOldQuotesBatch`
  - Criteria:
    - record type `Devis_appareil`
    - status `Draft`
    - `LastModifiedDate < today - 150 days`

### 2.4 Cancel/replace and original quote handling

Sources:
- `annuleDevisOrigine(...)`
- `majFieldHastobecancelled(...)`
- `PB_AbandonedQuotesWhenSecondaryQuoteBecomePrimary`

#### When a replacement/original quote chain is involved
- Original quote `SBQQ__Status__c = 'Abandoned'`
  - When a quote with `SBQQ__OriginalQuote__c` becomes `Accepted`.

#### When a presented quote is in cancel-and-replace mode
- `HasToBeSigned__c = true`
  - On the presented replacement quote when `CancelAndReplace__c = true`.

#### When a quote references an original quote
- Original quote `Hastobecancelled__c = true`

#### When one quote is promoted as the new primary contract quote
- Other quotes on the same opportunity can be mass-updated to:
  - `SBQQ__Status__c = 'Abandoned'`
  - Done by `PB_AbandonedQuotesWhenSecondaryQuoteBecomePrimary`
  - Excludes VT quotes

### 2.5 Financing fields

Source: `updateRequiredFieldsFRF(...)`.

When financing-related conditions are met:
- `Duree_credit__c`
- `Montant_credit__c`
- `Mensualite_FRF__c`
- `Montant_apport__c`

Behavior:
- If `Has_Conga_Pack__c = true`, financing values are recalculated from pack / interest logic.
- If financing is removed, fields are cleared:
  - `Duree_credit__c = null`
  - `Montant_credit__c = null`
  - `Mensualite_FRF__c = null`
  - `Montant_apport__c = null`

### 2.6 B2B2C quote enrichment

Source: active flow `QUO012_UpdateQuoteB2B2C_ME`.

This flow updates the quote passed as `NewQuote` with billing/client information:
- `TECH_ME_B2B2C_GID__c`
- `TECH_ME_B2B2C_Mail_facturation__c`
- `TECH_ME_B2B2C_Nom_Adresse_de_facturation__c`
- `TECH_ME_B2B2C_Adresse_de_facturation__c`
- `Client_demandeur__c`

### 2.7 Other quote field refreshes on update

#### Contract quote sent from email task

Source: `TR015_TaskTriggerHandler.updateQuotesAfterEmailIsSentWithRT(...)`.

For `PropositionContrat`, if the created email task subject contains `Proposition de contrat`:
- `SBQQ__Status__c = 'Sent for pre-contractual information'`
- `EnvoiPrecontractuelPar__c = UserInfo.getName()`
  - Only if blank.

#### Spare parts quote sent from email task

Source: same method.

For `Devis_Pieces`:
- `SBQQ__Status__c = 'Presented'`

#### Amount display helper

Source: `FillMontantApresCoupDePouceSansDecimales(...)`.

- `MontantApresCoupDePouceSansDecimales__c`
  - Recomputed from `Montant_apres_coup_de_pouce__c` and, in some cases, `TECH_Rollup_PEPA__c`.

## 3. Fields that are not auto-populated but are protected by automation

These do not set values, but they matter when documenting quote updates:
- On quotes already in terminal/business-controlled statuses, edits to many fields are blocked by `avoidEditionOnNonEditableFields(...)`.
- On status change to `Accepted`, automation validates billing-account and billing-address prerequisites before allowing save.
- When a primary quote is moved to `Rejected` or `Abandoned`, open work orders can block the change.

## 4. Practical summary

If we simplify the behavior:
- On create, the system mainly sets status, quote process, template/CGE fields, clone resets, and flow-provided context fields.
- On update, the system mainly reacts to status changes:
  - sent/presented -> sent dates and communication flags
  - accepted -> accepted dates, primary flags, signature fields
  - replacement/primary changes -> abandonment or cancel markers on related quotes
  - aging rules -> abandonment after timeout/inactivity

## 5. File references

- [CpqQuoteTrigger.trigger](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/triggers/CpqQuoteTrigger.trigger)
- [TR003_CPQQuoteTriggerHandler.cls](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/classes/TR003_CPQQuoteTriggerHandler.cls)
- [TR015_TaskTriggerHandler.cls](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/classes/TR015_TaskTriggerHandler.cls)
- [UniversignEventTrigger.trigger](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/triggers/UniversignEventTrigger.trigger)
- [QUO003_UpdateOpptyStatusOnContratQuoteStatus.flow-meta.xml](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/flows/QUO003_UpdateOpptyStatusOnContratQuoteStatus.flow-meta.xml)
- [QUO011_RT_TIMER_ExpiredQuote.flow-meta.xml](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/flows/QUO011_RT_TIMER_ExpiredQuote.flow-meta.xml)
- [QUO012_UpdateQuote.flow-meta.xml](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/flows/QUO012_UpdateQuote.flow-meta.xml)
- [PB_AbandonedQuotesWhenSecondaryQuoteBecomePrimary.flow-meta.xml](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/flows/PB_AbandonedQuotesWhenSecondaryQuoteBecomePrimary.flow-meta.xml)
- [DEV_VWF006_CpqQuoteAppareilCreation.flow-meta.xml](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/flows/DEV_VWF006_CpqQuoteAppareilCreation.flow-meta.xml)
- [DEV_VWF023_CpqQuotePrestationCreation.flow-meta.xml](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/flows/DEV_VWF023_CpqQuotePrestationCreation.flow-meta.xml)
- [AbandonOldQuotesBatch.cls](/abs/c:/Users/elisa.rita.moreira/OneDrive%20-%20Accenture/Documents/Salesforce/EHS/force-app/main/default/classes/AbandonOldQuotesBatch.cls)

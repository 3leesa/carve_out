/* Test class: TR005_CaseTriggerHandler_Test
* History Log:
* <06/09/2021> <Sprint 16> <MCOSF-838> <EDE> <Ajout d'un contrôle pour empêcher la clôtures des demandes ayant des devis liés.>
* <27/09/2021> <Sprint 17> <MCOSF-1002> <ASC> <Bloquer la création d'une demande de devis/pose avec équipement en doublon>
* <20/01/2022> <Sprint 22> <MCOSF-1287> <ASC> <Ajout du champ tech TECH_CreatedByUserRole__c pour récupérer le rôle du créateur de l'opp => Sharing>
* <31/05/2022> <Sprint 28> <MCOSF-1805> <ASC> <Ajout du remplissage du champ Type_equipement_propose__c au moment de la création de l'opportunité depuis la demande>
* <22/09/2022> <Sprint 33> <MCOSF- 1980-1992-1993> <SLI> <Guepard mettre en place le parcours RebondCo (Création de la demande fille de souscription et création opportunité)>
* <15/02/2023> <Sprint 40> <MCOSF-2382> <ASC> <Création d'une méthode pour détecter si la demande a été réattribuée>
* <02/04/2025> <Sprint 74> <MCOSF-5492> <EDE> <Refonte pour limiter les SOQL/DML>
* <15/05/2025> <Sprint 76> <MCOSF-5755> <EDE> <Correction de la méthode majCaseOwner, une condition était manquante>
* <17/09/2025> <Sprint 81> <MCOSF-6163> <EDE> <Modification de la méthode eContrat_afterProcessing>
*/
public class TR005_CaseTriggerHandler {
    public static String OPPORTUNITY_RECORDTYPE_B2C_CRM_ID {
        get {return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('CRM_B2C').getRecordTypeId();}
    }
    public static String OPPORTUNITY_RECORDTYPE_CONTRAT_ID {
        get {return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Contrat').getRecordTypeId();}
    }
    public static String OPPORTUNITY_RECORDTYPE_APPAREIL_AD_ID {
        get {return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Appareil_Agence_Digitale').getRecordTypeId();}
    }
    
    public static String CASE_RECORDTYPE_SOUSCRIPTION_ID {
        get {return Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Souscription').getRecordTypeId();}
    }
    public static String CASE_RECORDTYPE_POSEEQUIPEMENT_ID {
        get {return Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('PoseEquipement').getRecordTypeId();}
    }

    public static String OPPORTUNITY_RECORDTYPE_PRESTATION_HORS_CONTRAT_ID {
    get { 
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Prestation_Hors_Contrat').getRecordTypeId(); 
    }
    }

    public static Boolean firstRunMajCaseOwner = true;
    public static Boolean firstRunMajCaseOwnerAfterUpdate = true; //MCOSF-2573 : maj case owner after update
    public static Boolean firstRunMajWorkorderAssocies = true;
    public static Boolean firstRunMajSiteDeRattachement = true;
    public static Boolean firstRunMajSiteGestionnaire = true;
    public static Boolean firstRunMajOppOwner = true;
    public static Boolean firstRunCMIBeforeUpdate = true;
    public static Boolean firstRunCreerEchangeClient = true;
    public static Boolean firstRunflagCaseAsReattribuee = true;
    public static Boolean firstRuncreateTaskFromCaseEC = true;
    public static Boolean firstRunUpsertAll = true;
    public static Boolean firstRunCreateOppForPrestationHorsContrat = true;    

    public static Set<Id> userIds = new Set<Id>();
    public static Set<Id> parentCaseIds = new Set<Id>();
    public static Set<Id> assetIds = new Set<Id>();
    public static Set<Id> woIds = new Set<Id>();
    public static Set<Id> siteIds = new Set<Id>();
    
    public static Map<Id, User> usersMap = new Map<Id, User>();
    public static Map<Id, Case> parentCasesMap = new Map<Id, Case>();
    // public static Map<Id, List<Case>> relatedCasesMap = new Map<Id, List<Case>>();
    public static Map<Id, Asset> astMap = new Map<Id, Asset>(); 
    public static Set<WorkOrder> relatedWos = new Set<WorkOrder>();
    public static Map<Id, Agence__c> sitesMap = new Map<Id, Agence__c>();
    
    public static Map<Id, Logement__c> lgmtsToUpdateMap = new Map<Id, Logement__c>();
    public static Map<Id, Opportunity> oppToUpdateMap = new Map<Id, Opportunity>();
    public static Map<Id, Case> casesToUpdateMap = new Map<Id, Case>();
    public static List<Case> casesToCreate = new List<Case>();
    
    // MCOSF-5492 : The method queries all  records that are used in the trigger handler and the other methods called.
    public static void getRelatedRecords(List<Case> newCases, Map<Id, Case> oldCasesMap){
  
        Boolean hasNewUsers = false;
        Boolean hasSitesChanged = false;
        
        for(Case c : newCases){
            if(!userIds.contains(c.OwnerId) || !userIds.contains(c.LastModifiedById) || (oldCasesMap != null && 
                (!userIds.contains(oldCasesMap.get(c.Id).OwnerId) || !userIds.contains(oldCasesMap.get(c.Id).LastModifiedById)))){
                hasNewUsers = true;
                userIds.add(UserInfo.getUserId());
                userIds.add(c.OwnerId);
                userIds.add(c.LastModifiedById);
                if(oldCasesMap != null){
                    userIds.addAll(new Set<Id>{oldCasesMap.get(c.Id).LastModifiedById, oldCasesMap.get(c.Id).OwnerId});
                }
            }
            
            if(String.isNotBlank(c.ParentId)){
                parentCaseIds.add(c.ParentId);
            }
            
            assetIds.add(c.AssetId);
  
            if(!siteIds.contains(c.ChoixAgence__c)){
                hasSitesChanged = true;
                siteIds.add(c.ChoixAgence__c);
            }
        }
        // Déclencher ssi nouveaux users ajoutés au Set.
        if(hasNewUsers){
            usersMap = new Map<Id, User>([SELECT Id, IdGazelleAgence__c, IsAdmin__c, Username, UserRole.DeveloperName, UserRole.Name FROM User WHERE Id IN :userIds]);
        }
  
        // A priori, les autres sont à déclencher seulement en after et si la liste de filtre a été modifiée
                    parentCasesMap = new Map<Id, Case>([SELECT Id, Status, SiteDeRattachement__c, AssetId, Type, CreatedBy.IdGazelleAgence__c, RecordType.DeveloperName FROM Case WHERE Id IN :parentCaseIds]);
        // relatedCasesMap = new Map<Id, Case>([SELECT Id, ParentId, AccountId, AssetId FROM Case WHERE ParentId IN :newCasesMap.keySet()]);
        
        for(Case c : parentCasesMap.values()){
            assetIds.add(c.AssetId);
        }
        
        astMap = new Map<Id, Asset>([SELECT Id, Name, AccountId, Account.Name, Site__c, ProduitGeneriqueFonction__c, SEI__c, TECH_PhenixAssetId__c, ProduitCodeGenerique__c, Logement__c, TECH_LieACollectifSocial__c, TECH_UsageDuLogementHabitation__c,
                                     Logement__r.TECH_HasCaseCMI__c, Logement__r.Locataire__c, Logement__r.Locataire__r.PersonContactId,
                                     Logement__r.Proprietaire__c,  Logement__r.Proprietaire__r.PersonContactId, Logement__r.ProprietaireOccupant__c, TECH_CheckIfCTRActif__c
                                     FROM Asset WHERE Id IN :assetIds]);
    
        Set<String> filteringStatuses = new Set<String>{
            Label.InterventionRealise, Label.InterventionAbsentDefinitif, Label.InterventionTerDgi, Label.InterventionProgramme, Label.InterventionConfirme, Label.InterventionAvise
        };
        
        // newCases only has Ids on update.
        if(oldCasesMap != null){
          relatedWos = new Set<WorkOrder>([SELECT Id, CaseId, Status, StartDate, Case.Status, Case.Type, Case.ParentId, Case.Parent.Type,
                                             Case.LastModifiedById, Case.ChoixAgence__c, Case.SiteDeCreation__c, Case.lastModifiedBy.IDGazelleAgence__c
                                             FROM WorkOrder WHERE CaseId IN :newCases OR (Case.ParentId IN :newCases AND Case.Status = :Label.DemandeTermine
                                             AND Case.Parent.Type = :Label.DemandeVisiteEntretien AND Case.Parent.TECH_NombreInterventionARevoir__c > 0 
                                             AND Case.Type = :Label.DemandeDepannage AND Status IN :filteringStatuses)]);
        }
        else { // MCOSF-6080 start : On insert, oldCasesMap is null. For opportunities generated from child cases, we need to query Work Orders related the parent cases.
            Set<Id> caseParentIds = new Set<Id>();
            for (Case c : newCases) {
                if (c.ParentId != null) caseParentIds.add(c.ParentId);}
            if (!caseParentIds.isEmpty()) {
                relatedWos = new Set<WorkOrder>([SELECT Id, CaseId, StartDate, Status, LastModifiedDate FROM WorkOrder WHERE CaseId IN :caseParentIds]);
            }
        } // MCOSF-6080 end

            //Sites won't change, and should be shared between related cases. Query once if possible.
        if(sitesMap.isEmpty() || hasSitesChanged){
            sitesMap = new Map<Id, Agence__c>([SELECT Id, TECH_GazelleId__c, Name, AgencePilote__c, SiteParent__c, SiteParent__r.Name, 
                                           SiteParent__r.SiteParent__c, SiteParent__r.TECH_GazelleId__c, SiteParent__r.SiteParent__r.TECH_GazelleId__c 
                                           FROM Agence__c WHERE Id IN :siteIds]);
        }
    }
    
    public static void upsertAll(){
        if(!firstRunUpsertAll){
            return;
        }
        firstRunUpsertAll = false;
        List<Database.SaveResult> lstResults2 = Database.insert(casesToCreate, true);
        for(Integer i = 0; i< lstResults2.size(); i++){
            if (!lstResults2[i].isSuccess()) {
                casesToCreate[i].addError(lstResults2[i].getErrors()[0].getStatusCode() + ' - ' + lstResults2[i].getErrors()[0].getMessage());
            }
        }
        
        List<Database.SaveResult> lstResults = Database.update(casesToUpdateMap.values(), true);
        for(Integer i = 0; i< lstResults.size(); i++){
            if (!lstResults[i].isSuccess()) {
                casesToUpdateMap.values()[i].addError(lstResults[i].getErrors()[0].getStatusCode() + ' - ' + lstResults[i].getErrors()[0].getMessage());
            }
        }
    }
    
    /*
    * createOpportunityOnCase
    * Params : lstNewCases : Trigger.new
    * Trigger : Case.AFTER_INSERT
    * Description : Remplace le process builder REQ_PB003_CreerOpportuniteSurDemand. A la création d'une demande devis/pose, devis/pose AD ou souscription, crée une opportunité associée
    * <22/09/2022> <MCOSF-1993> <SLI> <Guepard: ajoute type de parent: dépannage et VE>
    */
    public static void createOpportunityOnCase(List<Case> lstNewCases) {
        System.debug('##### TR005_CaseTriggerHandler - createOpportunityOnCase -- BEGIN');
        
        // MCOSF-6080 START : This logic finds the most recently modified Work Order with a 'Confirmé' status (that triggered the creation of the child Case of type 'Souscription'), and uses its StartDate to populate the opportunity field EContratDateEntretien__c.
        Map<Id, WorkOrder> latestConfirmedWoByParentCaseId = new Map<Id, WorkOrder>();
        for (WorkOrder wo : relatedWos) { // on case insert relatedWos is populated with the work orders related to the parent cases of the child cases
            if (wo.Status == Label.InterventionConfirme) {
                if (!latestConfirmedWoByParentCaseId.containsKey(wo.CaseId) || 
                    wo.LastModifiedDate > latestConfirmedWoByParentCaseId.get(wo.CaseId).LastModifiedDate) {
                    latestConfirmedWoByParentCaseId.put(wo.CaseId, wo);
                }
            }
        } // MCOSF-6080 END

        /* // commented for MCOSF-6080 : this block creates a map of Work Orders based on the created child case's ID, not the parent case's ID as requested for the creation of a child case of type Souscription.
        List<WorkOrder> lstWO = new List<WorkOrder>(); //MCOSF-2346
        
        List<Id> lstCaseId = new List<Id>();
        for (Case c : lstNewCases) {
            lstCaseId.add(c.Id);
        }
        
        Map<Id, WorkOrder> workOrderByCaseId = new Map<Id, WorkOrder>();
        Set<Id> setParentCaseId = new Set<Id>(); //MCOSF-2346
        for (Case c : lstNewCases) {
            if (c.RecordTypeId == CASE_RECORDTYPE_SOUSCRIPTION_ID) {
                setParentCaseId.add(c.ParentId);
            }
        }

        // MCOSF-5492 : Code refactored to avoid SOQL
        for(WorkOrder wo : relatedWos){ // MCOSF-6080 : relatedWos is empty on the insert of the case (hence, we were not able to access the StartDate value of relatedWos to fill the opportunity field EContratDateEntretien__c)
            if (lstCaseId.contains(wo.CaseId) && workOrderByCaseId.get(wo.CaseId) == null) {
                workOrderByCaseId.put(wo.CaseId, wo);
            }
        } */

        // for (WorkOrder wo : [SELECT CaseId, StartDate FROM WorkOrder WHERE CaseId IN :lstCaseId ORDER BY StartDate DESC]){
        //   if (workOrderByCaseId.get(wo.CaseId) == null) {
        //     workOrderByCaseId.put(wo.CaseId, wo);
        //   }
        // }

        // lstNewCases = [SELECT Id, CaseNumber, Type, Motif_Souscription__c, Createur_Agence_Digitale__c, AccountId, ChoixAgence__c,
        //               OppDateEcheance__c, TECH_NomOpportunite__c, OppMiseEnConcurrence__c, Type_equipement_propose__c,
        //               ParentId, Parent.Type, Parent.CreatedBy.IDGazelleAgence__c, 
        //               AssetId, Asset.TECH_LieACollectifSocial__c, Asset.Logement__c, Asset.ProduitCodeGenerique__c
        //               FROM Case WHERE Id IN :lstCaseId];
        
        // User userInfos = [SELECT Id, UserRole.Name, IDGazelleAgence__c FROM User WHERE Id = :UserInfo.getUserId()];
        User userInfos = usersMap.get(UserInfo.getUserId());
        
        List<Opportunity> lstOppToCreate = new List<Opportunity>();
        List<String> caseIdList = new List<String>(); // MCOSF-3571 - Added
        
        List<String> motifSouscriptionLst = Label.CL_MOTIF_SOUSCRIPTION_LISTE.split(',');
        
        System.debug('##### List<Case> : ' + JSON.serialize(lstNewCases));
        for (Case c : lstNewCases) {
            Asset ast = astMap.get(c.AssetId);
            WorkOrder confirmedWo = latestConfirmedWoByParentCaseId.get(c.ParentId); // MCOSF-6080 : get the latest confirmed WO related to the parent Case of the child Case c 
            //demande de pose
            if (c.Type != null && c.Type.contains('Pose') && !c.Createur_Agence_Digitale__c && ast?.TECH_LieACollectifSocial__c == false){
                Opportunity newOpp = new Opportunity(CloseDate = c.OppDateEcheance__c, 
                                                     Name = c.TECH_NomOpportunite__c, 
                                                     StageName = 'Besoin détecté',
                                                     Sous_statut__c = 'RDV à positionner', 
                                                     AccountId = c.AccountId, 
                                                     ChoixAgence__c = c.ChoixAgence__c,
                                                     Demande__c = c.Id, 
                                                     LogementConcerne__c = ast.Logement__c, 
                                                     Type = 'Equipement',
                                                     MiseEnConcurrence__c = c.OppMiseEnConcurrence__c, 
                                                     TECH_DateCreationDemandeMere__c = DateTime.now(),
                                                     TECH_CreatedByUserRole__c = userInfos.UserRole.Name, 
                                                     Type_equipement_propose__c = c.Type_equipement_propose__c,
                                                     RecordtypeId = OPPORTUNITY_RECORDTYPE_B2C_CRM_ID);
                lstOppToCreate.add(newOpp);
            }
            
            //demande de pose AD
            if (c.Type != null && c.Type.contains('Pose') && c.Createur_Agence_Digitale__c) {
                Opportunity newOpp = new Opportunity(CloseDate = c.OppDateEcheance__c, 
                                                     Name = c.TECH_NomOpportunite__c, 
                                                     StageName = 'Besoin détecté',
                                                     Sous_statut__c = 'RDV à positionner',  
                                                     AccountId = c.AccountId, 
                                                     ChoixAgence__c = c.ChoixAgence__c,
                                                     Demande__c = c.Id, 
                                                     LogementConcerne__c = ast.Logement__c, 
                                                     Type = 'Equipement', 
                                                     MiseEnConcurrence__c = 
                                                     c.OppMiseEnConcurrence__c,
                                                     TECH_DateCreationDemandeMere__c = DateTime.now(),
                                                     TECH_CreatedByUserRole__c = userInfos.UserRole.Name, 
                                                     Type_equipement_propose__c = c.Type_equipement_propose__c,
                                                     RecordtypeId = OPPORTUNITY_RECORDTYPE_APPAREIL_AD_ID);
                lstOppToCreate.add(newOpp);
            }
            
            //demande de souscription
            
            //MCOSF 1993 - Guépard parcour RebondCo ajouter type de parent: dépannage et VE
            CPQ_MappingTypeEquipement__mdt equipement = (Test.isRunningTest()) ? null : CPQ_MappingTypeEquipement__mdt.getInstance(ast?.ProduitCodeGenerique__c);
            //MCOSF-3194 : Souscription Web - Creer Opp si Demande souscription + Motif de souscription est Parcours Web
            System.debug ('EDER Debugs : ' + c.Type + ' ' + c.ParentId + ' ' + c.Motif_Souscription__c);
            if (c.Type == 'Souscription' &&  (String.isNotBlank(c.ParentId) && motifSouscriptionLst.contains(c.Motif_Souscription__c)) ||
                c.Motif_Souscription__c ==  Label.CL_MOTIF_SOUSCRIPTION_MES_TEL || c.Motif_Souscription__c ==  Label.CL_MOTIF_SOUSCRIPTION_PARCOURS_WEB){
                    //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro
                    if (c.Motif_Souscription__c != Label.CL_MOTIF_SOUSCRIPTION_PARCOURS_WEB) {
                        System.debug('##### type de demande : ' + c.type);
                        Opportunity newOpp = new Opportunity(Name = c.TECH_NomOpportunite__c, 
                                                             StageName = 'Besoin détecté', 
                                                             AccountId = c.AccountId, 
                                                             ChoixAgence__c = c.ChoixAgence__c, 
                                                             Demande__c = c.Id, 
                                                             LogementConcerne__c = ast.Logement__c,
                                                             MiseEnConcurrence__c = c.OppMiseEnConcurrence__c, 
                                                             Type = 'Contrat / option',
                                                             RecordtypeId = OPPORTUNITY_RECORDTYPE_CONTRAT_ID, 
                                                             TECH_DateCreationDemandeMere__c = DateTime.now(),
                                                             TECH_CreatedByUserRole__c = userInfos.UserRole.Name);
                        
                        if (confirmedWo != null) {newOpp.EContratDateEntretien__c = confirmedWo.StartDate;} // MCOSF-6080 : Use the latest confirmed WO's StartDate
                        // newOpp.EContratDateEntretien__c = workOrderByCaseId.get(c.Id)?.StartDate ?? workOrderByCaseId.get(c.ParentId)?.StartDate; // commented for MCOSF-6080
                        newOpp.CloseDate = c.OppDateEcheance__c ?? (Date.today() + 365);
                        newOpp.TECH_CreatedByUserSite__c = parentCasesMap.get(c.ParentId)?.CreatedBy.IDGazelleAgence__c ?? userInfos.IDGazelleAgence__c;
                        newOpp.Type_equipement_propose__c = equipement?.TypeEquipementPropose__c;
                        lstOppToCreate.add(newOpp);
                    }
                    //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro - START
                    if (c.Motif_Souscription__c == Label.CL_MOTIF_SOUSCRIPTION_PARCOURS_WEB) {
                        caseIdList.add(c.Id);
                    }
                    //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro - END
                }
        }
        if(lstOppToCreate.size() > 0) {
            Database.insert(lstOppToCreate, false);
        }
        //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro - START
        if (caseIdList.size() > 0 && !Test.isRunningTest()) {
            System.enqueueJob(new CaseQueueable(caseIdList));
        }
        //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro - END
        System.debug(
            '##### TR005_CaseTriggerHandler - createOpportunityOnCase -- END'
        );
    }

    /**
    * NEW FEATURE - 2025-11-20 - MCOSF 6279
    * Params : lstNewCases : Trigger.new
    * Trigger : Case.AFTER_INSERT
    * Creates "Prestation Hors Contrat" Opportunity when a "Visite / Entretien" case
    * is created on an Asset with no active contract
    */
    public static void createOppForPrestationHorsContrat(List<Case> newCases) {
    System.debug('##### TR005_CaseTriggerHandler - CreateOppForPrestationHorsContrat -- BEGIN');

    if (!firstRunCreateOppForPrestationHorsContrat) return;
    firstRunCreateOppForPrestationHorsContrat = false;

    List<Opportunity> oppsToInsert = new List<Opportunity>();

    for (Case newCase : newCases) {
        
        if (newCase.Type != 'Visite / Entretien' 
            || newCase.CategorieDemande__c != '5' 
            || newCase.AssetId == null) {
            continue;
        }

        Asset relatedAsset = astMap.get(newCase.AssetId);
        if (relatedAsset == null) continue;

        if (relatedAsset.TECH_CheckIfCTRActif__c == false) {

                String oppName = 'Prestation Hors Contrat - ' + relatedAsset.Account.Name + ' - ' + relatedAsset.Name;

            Opportunity opp = new Opportunity(
                RecordTypeId              = OPPORTUNITY_RECORDTYPE_PRESTATION_HORS_CONTRAT_ID,
                Name                      = oppName,
                Type                      = 'Accessoire et prestations',
                StageName                 = 'Besoin détecté',
                CloseDate                 = Date.today().addDays(90),
                AccountId                 = newCase.AccountId,
                Type_equipement_propose__c = newCase.Type_equipement_propose__c,
                B2B_canal_de_contact__c   = newCase.Origin,
                OwnerId                   = newCase.OwnerId,
                Demande__c                = newCase.Id,
                ChoixAgence__c            = newCase.ChoixAgence__c,
                LogementConcerne__c       = newCase.TECH_LogementId__c
            );

            oppsToInsert.add(opp);
        }
    }

    if (!oppsToInsert.isEmpty()) {
        Database.insert(oppsToInsert, false);
    }

    System.debug('##### TR005_CaseTriggerHandler - CreateOppForPrestationHorsContrat -- END');
    }
    //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro - START
    public class CaseQueueable implements System.Queueable {
        private List<String> caseIdList;
        
        public CaseQueueable(List<String> caseIds) {
            this.caseIdList = caseIds;
        }
        
        public void execute(System.QueueableContext context) {
            createOpportunityOnCaseParcoursWeb(caseIdList);
        }
    }
    
    public static void createOpportunityOnCaseParcoursWeb(List<String> caseIdList) {
        User userInfos = [SELECT Id, UserRole.Name, IDGazelleAgence__c FROM User WHERE Id = :UserInfo.getUserId()];
        //User userInfos = usersMap.get(UserInfo.getUserId());
        
        List<Opportunity> lstOppToCreate = new List<Opportunity>();
        List<Case> caseList = [SELECT Id, CaseNumber, Type, TECH_NomOpportunite__c, AccountId, ChoixAgence__c, ParentId,
                               Type_equipement_propose__c, OppDateEcheance__c, Motif_Souscription__c, OppMiseEnConcurrence__c,
                               DateDebutSouhaitee__c, CreneauSouhaite__c, Parent.CreatedBy.IDGazelleAgence__c,
                               Asset.Logement__c, Asset.ProduitCodeGenerique__c
                               FROM Case WHERE Id IN :caseIdList ];
        
        system.debug('MJS-caseList: ' + caseList);
        Map<Id, WorkOrder> workOrderByCaseId = new Map<Id, WorkOrder>();
        
        for (WorkOrder wo : [SELECT CaseId, StartDate FROM WorkOrder WHERE CaseId IN :caseIdList ORDER BY StartDate DESC ]) {
            if (workOrderByCaseId.get(wo.CaseId) == null) {
                workOrderByCaseId.put(wo.CaseId, wo);
            }
        }
        
        for (Case c : caseList) {
            CPQ_MappingTypeEquipement__mdt equipement = CPQ_MappingTypeEquipement__mdt.getInstance(c.Asset.ProduitCodeGenerique__c);
            
            String DateDebutSouhaitee = (c.DateDebutSouhaitee__c != null) ? String.valueof(c.DateDebutSouhaitee__c) : null;
            String CreneauSouhaite = (c.CreneauSouhaite__c != null) ? c.CreneauSouhaite__c : null;
            
            Opportunity newOpp = new Opportunity(Name = c.TECH_NomOpportunite__c, 
                                                 StageName = 'Besoin détecté', 
                                                 AccountId = c.AccountId,
                                                 ChoixAgence__c = c.ChoixAgence__c, 
                                                 Demande__c = c.Id, 
                                                 LogementConcerne__c = c.Asset.Logement__c,
                                                 MiseEnConcurrence__c = c.OppMiseEnConcurrence__c, 
                                                 RecordtypeId = OPPORTUNITY_RECORDTYPE_CONTRAT_ID,
                                                 TECH_DateCreationDemandeMere__c = DateTime.now(), 
                                                 TECH_CreatedByUserRole__c = userInfos.UserRole.Name,
                                                 Type = 'Contrat / option', 
                                                 Date_de_signature_du_devis__c = Date.today(),
                                                 DateDebutSouhaiteeCreneau__c = DateDebutSouhaitee + ' - ' + CreneauSouhaite);
            
            newOpp.EContratDateEntretien__c = workOrderByCaseId.get(c.Id)?.StartDate ?? workOrderByCaseId.get(c.ParentId)?.StartDate;
            newOpp.CloseDate = c.OppDateEcheance__c ?? Date.today() + 365;
            newOpp.TECH_CreatedByUserSite__c = c.Parent?.CreatedBy.IDGazelleAgence__c ?? userInfos.IDGazelleAgence__c;
            newOpp.Type_equipement_propose__c = equipement?.TypeEquipementPropose__c;
            lstOppToCreate.add(newOpp);
            system.debug('MJS-lstOppToCreate: ' + lstOppToCreate);
        }
        
        if (lstOppToCreate.size() > 0) {
            Database.insert(lstOppToCreate, false);
        }
    }
    //MCOSF-3571 : Recette parcours web - Creer Opp en Asynchro - END
    
    /*
    * createDemandeFilleSurDemande
    * Params : lstCaseId : List<Id>
    * Trigger : Case.AFTER_INSERT, Case.AFTER_UPDATE
    * Description : Remplace le process builder REQ_PB010_CreerDemandeFilleSurDemandeMES.  A la création/modification 
    *              d'une demande de Mise en Service crée une demande fille de type Souscription selon l'avancement MES
    * Mise à jour : 2021-03-02 - ASC: Vérifier qu'il n'y a pas de Demande Fille Souscription existante non clôturée avant d'en créer une nouvelle
    *               2022-09-20 - SLI: Guépard - Ajouter parcours RebondCo Création de la demande fille de souscription, 
    *                                remplacer le nom de createDemandeFilleSurDemandeMESpar createDemandeFilleSurDemande
    */
    
    //MCOSF-5492 : the method was only called at the end of eContrat_afterProcessing. It is included in its refactoring.
    
    // public static void createDemandeFilleSurDemande(List<Id> lstCaseId) {
    //   System.debug('##### TR005_CaseTriggerHandler - createDemandeFilleSurDemande -- BEGIN');
    //   System.debug('##### lstCaseId : ' + lstCaseId);
    //   List<Case> lstRetrievedCases = [SELECT Id, Type, BusinessHoursId, AccountId, AssetId, ChoixAgence__c, ContactId, Duree_du_contrat__c,
    //                                   OppDateEcheance__c, CMI_MES_faite_avec_le_conducteur__c,  Origine_de_la_demande__c,
    //                                   ChoixAgence__r.TECH_GazelleId__c, SiteDeRattachement__r.AgencePilote__c, Asset.TECH_UsageDuLogementHabitation__c
    //                                   FROM Case WHERE Id IN :lstCaseId];
    
    //   Map<Id, Case> mapDemandeFilleParParent = new Map<Id, Case>();
    //   List<Case> lstDemandesFillesExistantes = [SELECT ParentId, Id FROM Case WHERE ParentId IN :lstCaseId 
    //                                             AND Type = 'Souscription' AND Status != 'Terminé'];
    //   if (lstDemandesFillesExistantes.size() > 0) {
    //     for (Case c : lstDemandesFillesExistantes) {
    //       mapDemandeFilleParParent.put(c.ParentId, c);
    //     }
    //   }
    
    //   List<Case> lstCaseToCreate = new List<Case>();
    //   for (Case c : lstRetrievedCases) {
    //     Case newCase = new Case(BusinessHoursId = c.BusinessHoursId, AccountId = c.AccountId, AssetId = c.AssetId, ChoixAgence__c = c.ChoixAgence__c,
    //                             ContactId = c.ContactId, Duree_du_contrat__c = c.Duree_du_contrat__c, OppDateEcheance__c = c.OppDateEcheance__c,
    //                             Origin = 'Interne', ParentId = c.Id, RecordtypeId = CASE_RECORDTYPE_SOUSCRIPTION_ID, Type = 'Souscription');
    //     // MCOSF-3816 : Anomalie statut demande de souscription EContrat
    //     if (c.CMI_MES_faite_avec_le_conducteur__c &&  c.Origine_de_la_demande__c == 'CMI') {
    //       newCase.Status = 'En cours';
    //       newCase.Sous_statut__c = 'Client à appeler';
    //     } 
    //     else {
    //       newCase.Status = 'Nouveau';
    //     }
    //     // Parcour CMISTE
    //     if (c.Type == Label.CL_TYPE_MES && c.Origine_de_la_demande__c == 'CMI') {
    //       newCase.Motif_Souscription__c = Label.CL_MOTIF_SOUSCRIPTION_MES_CMI;
    //     }
    //     // Parcours RebondCo encours
    //     if (c.SiteDeRattachement__r.AgencePilote__c && c.asset.TECH_UsageDuLogementHabitation__c) {
    //       if (c.Type == Label.CL_TYPE_MES && c.Origine_de_la_demande__c == 'Autre' ) {
    //         newCase.Motif_Souscription__c = Label.CL_MOTIF_SOUSCRIPTION_MES_AUTRE;
    //       } 
    //       else if (c.Type == Label.CL_TYPE_DEP) {
    //         newCase.Motif_Souscription__c = Label.CL_MOTIF_SOUSCRIPTION_DEPANNAGE;
    //       } 
    //       else if (c.Type == Label.DemandeVisiteEntretien) {
    //         newCase.Motif_Souscription__c = Label.CL_MOTIF_SOUSCRIPTION_VE;
    //       }
    //     }
    //     newCase.Subject = newCase.Motif_Souscription__c;
    
    //     if (mapDemandeFilleParParent.get(c.Id) == null && newCase.Motif_Souscription__c != null) {
    //       lstCaseToCreate.add(newCase);
    //     }
    //   }
    
    //   if (lstCaseToCreate.size() > 0) {
    //     Database.insert(lstCaseToCreate, false);
    //   }
    
    //   System.debug('##### TR005_CaseTriggerHandler - createDemandeFilleSurDemande -- END');
    // }

    // MCOSF-6272 : set DemandeUrgente__c field based on InformationCRC__c value 
    public static void beforeInsertProcessingDemandeUrgente(List<Case> Cases) {
        for(Case caseRecord : Cases) {
            if (String.isNotBlank(caseRecord.InformationCRC__c)) {
                caseRecord.DemandeUrgente__c = AP_DemandeUrgente.getCalculatedUrgence(caseRecord.InformationCRC__c, caseRecord.DemandeUrgente__c);
            }
        }
    }

    // CaseBeforeUpdate refactoring
    public static void beforeUpdateProcessing(List<Case> Cases) {
        // List<Id> siteIdList = new List<Id>();
        List<Id> casesNew = new List<Id>();
        List<Id> casesToApprove = new List<Id>();
        
        for (Case caseToSite : Cases) {
            // if (String.isNotBlank(caseToSite.ChoixAgence__c)) {
            //   siteIdList.add(caseToSite.ChoixAgence__c);
            // }
            if (caseToSite.Status != Label.DemandeTermine &&String.isNotBlank(caseToSite.ParentId)) {
                casesNew.add(caseToSite.ParentId);
            }
            if (caseToSite.Status == 'En attente d\'approbation' && caseToSite.Type == 'Réclamation' && caseToSite.Approbateur_1__c != null &&
                caseToSite.Origin != 'Téléphone' && caseToSite.Origin != 'Visite en agence' && (caseToSite.ReponseParEmail__c || caseToSite.ReponseParCourrier__c)) {
                    casesToApprove.add(caseToSite.Id);
                }
            // added for MCOSF-6272 : use of the existing for loop to set DemandeUrgente__c field based on InformationCRC__c value
            if (String.isNotBlank(caseToSite.InformationCRC__c)) {
                caseToSite.DemandeUrgente__c = AP_DemandeUrgente.getCalculatedUrgence(caseToSite.InformationCRC__c,caseToSite.DemandeUrgente__c);
            }
        }
        
        //Send case IDs for processing
        if (sitesMap.size() > 0) {
            AP_FillSiteParentGazelleId.updateCases(sitesMap, cases);
        }
        
        // CRM 675 - BUG - Permettre le système d'approbation lorsqu'un approbateur est inactif
        if (casesToApprove.size() > 0) {
            AP_UpdateCaseToApprove.updateCasesToApprove(casesToApprove);
        }
    }
    
    //MCOSF-4042 : TR005 : basculer la methode updateRelatedCaseStatusClosed() en after Update - START
    public static void afterUpdateProcessing(List<Case> Cases) {
        List<ID> casesClosed = new List<ID>();
        
        for (Case caseToSite : Cases) {
            if (caseToSite.Status == Label.DemandeTermine && String.isNotBlank(caseToSite.ParentId)){
                casesClosed.add(caseToSite.ParentId);
            }
        }
        // CRM 624-633 - Update du dossier détracteurs associé au case
        if (casesClosed.size() > 0) {
            AP_UpdateCaseDossierDetracteur.updateRelatedCaseStatusClosed(casesClosed, parentCasesMap, casesToUpdateMap);
        }
    }
    //MCOSF-4042 : TR005 : basculer la methode updateRelatedCaseStatusClosed() en after Update - END
    
    // CaseBeforeUpdate Refactoring - CMI + Empêchement clôture demande
    public static void CMI_beforeUpdateProcessing(List<Case> newCases, Map<Id, Case> oldCasesMap, Map<Id, Case> newCasesMap) {
        if (firstRunCMIBeforeUpdate){
            firstRunCMIBeforeUpdate = false;
            List<Id> casesCMIEnquete = new List<Id>();
            //system.debug('MJS-TEST-newCases: ' + newCases);
            /* See MCOSF-6280
            for (Case c : newCases) {
                if (c.Origine_de_la_demande__c == 'CMI' && c.CMI_Avancement_MES__c == Label.CL_StatusEnqueteCMI &&
                    oldCasesMap.get(c.id).CMI_Avancement_MES__c != newCasesMap.get(c.id).CMI_Avancement_MES__c) {
                        casesCMIEnquete.add(c.Id);
                    }
            }
            */
            //System.debug('MJS-TEST-casesCMIEnquete1: ' + casesCMIEnquete);
            
            //MEL CRM-100
            AP_EmpecherClotureDemande.checkIntervention(newCases, oldCasesMap, relatedWos);
            
            // DEVMCO-838
            if (!Label.IdTechUsersBypassingOpenQuoteCtrlOnCase.contains(UserInfo.getUserId())){
                AP_EmpecherClotureDemande.preventClosingIfRelatedOpenQuotesExist(newCases, oldCasesMap);
            }
            /* See MCOSF-6280
            // CRM 626 Envoi de l'enquête de satisfaction MediaTech
            if (casesCMIEnquete.size() > 0) {
                //system.debug('MJS-TEST-casesCMIEnquete2: ' + casesCMIEnquete);
                AP_EnvoiEnqueteCMI.envoiEnqueteCMI(casesCMIEnquete);
            }
            */
        }
    }
    
    // CaseAfterInsert Refactoring
    public static void afterInsertProcessing(List<Case> newCases) {
        //check for the asset on the case.
        //check if there is previous case of lov VE exists or not
        //if exists then close it with future method
        //if not then do nothing.
        
        // MCOSF-5492 : Code refactoring to avoid SOQLs
        Set<Id> astIds = new Set<Id>();
        Set<Id> triggeringCasesId = new Set<Id>();
        //Set<String> CaseIds = new Set<String>();
        
        // MCOSF-5492 : filtering on astMapv(asset.Logement__c/r) and sitesMap rather than on Ids with future query filtering
        // List<Id> LogementIds = new List<Id>();
        // List<Id> SiteIds = new List<Id>();
        Map<Logement__c, Agence__c> lgmtMapSite = new Map<Logement__c, Agence__c>();
        Map<Id, String> parentIdMapCaseNumber = new Map<Id, String>();
        // Map<Id, List<Case>> mapCaseParentId2LstCases = new Map<Id, List<Case>>();
        
        for (Case caseToSend : newCases) {
            if (String.isNotBlank(caseToSend.NumLot__c)) {
                astIds.add(caseToSend.AssetId);
                triggeringCasesId.add(caseToSend.Id);
                // CaseIds.add(caseToSend.Id);
            }
            
            // MCOSF-5492, refactoring avec prise en compte de la condition  caseToSend.TECH_LogementId__c = true venant de  AP_updateCases.updateLogmentCMI
            // if (caseToSend.Origine_de_la_demande__c == 'CMI' && String.isNotBlank(caseToSend.TECH_LogementId__c)) {
            //  LogementIds.add(caseToSend.TECH_LogementId__c);
            //  SiteIds.add(caseToSend.ChoixAgence__c);
            // }
            if(caseToSend.Origine_de_la_demande__c == 'CMI' && String.isNotBlank(caseToSend.ChoixAgence__c) && caseToSend.AssetId != null && astMap.get(caseToSend.AssetId) != null &&
               astMap.get(caseToSend.AssetId)?.Logement__r?.TECH_HasCaseCMI__c) {
                   
                   lgmtMapSite.put(astMap.get(caseToSend.AssetId).Logement__r, sitesMap.get(caseToSend.ChoixAgence__c));
               }
            if (caseToSend.Status != Label.DemandeTermine && String.isNotBlank(caseToSend.ParentId)) {
                //MCOSF-5492 :No longer needed. Done in upsertRelatedRecords.
                //création d'une map pour avoir la liste des cases enfant correspondant à un caseID parent (pour la gestion des erreurs sur le case)
                // List<Case> lstCaseTemp = new List<Case>();
                // if (mapCaseParentId2LstCases != null && mapCaseParentId2LstCases.containsKey(caseToSend.ParentId)) {
                //   lstCaseTemp = mapCaseParentId2LstCases.get(caseToSend.ParentId);
                // }
                // lstCaseTemp.add(caseToSend);
                // mapCaseParentId2LstCases.put(caseToSend.ParentId, lstCaseTemp);
                
                parentIdMapCaseNumber.put(caseToSend.ParentId, caseToSend.CaseNumber);
            }
        }
        
        //Send list of lot VE cases after creating them in salesforce for processing. (final treatment in future Apex)
        // if (astIds.size() > 0) {
        //   AP_updateCases.updateCaseStatus(CaseIds);
        // }
        AP_updateCases.updateCaseStatus(astIds, triggeringCasesId);
        
        AP_updateCases.updateLogmentCMI(lgmtMapSite, lgmtsToUpdateMap);
        
        // CRM 624-633 - Update du dossier détracteurs associé au case
        // MCOSF-673 - passer les parents à modifier + info de l'enfant déclenchant l'update pour mettre le adderror dessus en cas de besoin.
        if (parentIdMapCaseNumber.size() > 0) {
            AP_UpdateCaseDossierDetracteur.updateRelatedCaseStatusNew(parentIdMapCaseNumber, parentCasesMap, casesToUpdateMap);
        }
    }
    
    //factoriser CMI et RebondCo
    // MCOSF-2416 Evolution de parcours Cmist et Rebond, Création de la demande fille suite à la confirmation du RDV
    
    //MCOSF-5492 : The method does nothing if isInsert is false. Code refactoring, including createDemandeFilleSurDemande
    
    // public static void eContrat_afterProcessing(List<Case> newCases, Map<Id, Case> oldCasesMap, Boolean isInsert) {
    //   List<Id> lstCaseIdToProcess = new List<Id>();
    //   Set<String> caseTypes = new Set<String>{Label.CL_TYPE_MES, Label.CL_TYPE_DEP, Label.DemandeVisiteEntretien};
    
    //   for (Case c : newCases) {
    //     if (isInsert) {
    //       if (caseTypes.contains(c.Type) && String.isNotBlank(c.CMI_Avancement_MES__c) && c.CMI_Avancement_MES__c == Label.CL_CASE_RDV_CONFIRME &&
    //           oldCasesMap?.get(c.Id)?.CMI_Avancement_MES__c != Label.CL_CASE_RDV_CONFIRME
    //       ) {
    //         lstCaseIdToProcess.add(c.Id);
    //       }
    //     }
    //   }
    //   if (lstCaseIdToProcess.size() > 0) {
    //     createDemandeFilleSurDemande(lstCaseIdToProcess);
    //   }
    // }    
    
    public static void eContrat_afterProcessing(List<Case> newCases) {

        List<Id> lstCaseId = new List<Id>();
        Set<String> caseTypes = new Set<String>{Label.CL_TYPE_MES, Label.CL_TYPE_DEP, Label.DemandeVisiteEntretien};
        Set<Id> excludedCasesIds = new Set<Id>();
        
        //MCOSF-6163 : "AND Status != 'Terminé'" removed from the SOQL : It could cause multiple Case creation.
        for(Case c : [SELECT ParentId FROM Case WHERE ParentId IN :newCases AND Type = 'Souscription']){
            excludedCasesIds.add(c.ParentId);
        }

        for (Case c : newCases) {
            if (!excludedCasesIds.contains(c.Id) && caseTypes.contains(c.Type) && c.CMI_Avancement_MES__c == Label.CL_CASE_RDV_CONFIRME && c.Status != 'Terminé') {
                String motifSoucription;
                
                // Parcour CMISTE
                if (c.Type == Label.CL_TYPE_MES && c.Origine_de_la_demande__c == 'CMI') {
                    motifSoucription = Label.CL_MOTIF_SOUSCRIPTION_MES_CMI;
                }
                // Parcours RebondCo encours
                if (astMap.get(c.AssetId)?.TECH_UsageDuLogementHabitation__c == true) { // mcosf-6267 removed : sitesMap.get(c.ChoixAgence__c)?.AgencePilote__c == true --> AgencePilote__c is actually 23/10/2025 obsolete
                    if (c.Type == Label.CL_TYPE_MES && c.Origine_de_la_demande__c == 'Autre' ) {
                        motifSoucription = Label.CL_MOTIF_SOUSCRIPTION_MES_AUTRE;
                    } 
                    else if (c.Type == Label.CL_TYPE_DEP) {
                        motifSoucription = Label.CL_MOTIF_SOUSCRIPTION_DEPANNAGE;
                    } 
                    else if (c.Type == Label.DemandeVisiteEntretien) {
                        motifSoucription = Label.CL_MOTIF_SOUSCRIPTION_VE;
                    }
                }
                
                if(String.isNotBlank(motifSoucription)){
                    casesToCreate.add(new Case(BusinessHoursId = c.BusinessHoursId, AccountId = c.AccountId, AssetId = c.AssetId, 
                                               ChoixAgence__c = c.ChoixAgence__c,ContactId = c.ContactId, Duree_du_contrat__c = c.Duree_du_contrat__c, 
                                               OppDateEcheance__c = c.OppDateEcheance__c, Origin = 'Interne', ParentId = c.Id, 
                                               RecordtypeId = CASE_RECORDTYPE_SOUSCRIPTION_ID, Type = 'Souscription', 
                                               Motif_Souscription__c = motifSoucription, Subject = motifSoucription, 
                                               Status = (c.CMI_MES_faite_avec_le_conducteur__c &&  c.Origine_de_la_demande__c == 'CMI') ? 'En cours' : 'Nouveau',
                                               Sous_statut__c = (c.CMI_MES_faite_avec_le_conducteur__c &&  c.Origine_de_la_demande__c == 'CMI') ? 'Client à appeler' : ''));
                }
            }
        }
    }
    
    // Vérification pour empêcher l'insertion de demandes en doublon
    // MCOSF-5492 : This method checks duplicate creation in the last minute instead of today. 
    //              As it works in extremely limited scenarios and has never been declared as a bug, it is commented.
    // public static void preventDuplicateCreation(List<Case> newCases, Boolean isAdmin) {
    
    //   System.debug('### TR005 - preventDuplicateCreation - BEGIN');
    
    //   Set<Id> accountsIdSet = new Set<Id>();
    //   Set<Id> assetsIdSet = new Set<Id>();
    //   Map<String, Case> mapCaseInfoWithCase = new Map<String, Case>();
    
    //   for (Case c : newCases) {
    //     // key: AccountId, Type, AssetId, now(yyyy-mm-dd'T'HH:mm)
    //     String caseInfo = String.valueOf(c.AccountId) + c.Type + String.valueOf(c.AssetId) + String.valueOf((DateTime.now().format('yyyy-MM-dd\'T\'HH:mm')));
    //     if (mapCaseInfoWithCase.get(caseInfo) == null) {
    //       accountsIdSet.add(c.AccountId);
    //       assetsIdSet.add(c.AssetId);
    //       mapCaseInfoWithCase.put(caseInfo, c);
    //     }
    //   }
    
    //   // Récupération des cases crées précédemment dans la journée
    //   for (Case existingCase : [SELECT Id, AccountId, AssetId, CreatedDate, Type FROM Case WHERE AccountId IN :accountsIdSet
    //       AND AssetId IN :assetsIdSet AND CreatedDate = TODAY AND Status NOT IN ('Annulée', 'Terminé')]) {
    //     // key: AccountId, Type, AssetId, CreatedDate(yyyy-mm-dd'T'HH:mm)
    //     String existingCaseInfo = String.valueOf(existingCase.AccountId) + existingCase.Type + String.valueOf(existingCase.AssetId) +
    //                               String.valueOf((existingCase.CreatedDate).format('yyyy-MM-dd\'T\'HH:mm'));
    //     if (!Test.isRunningTest() && !isAdmin && mapCaseInfoWithCase.get(existingCaseInfo) != null) {
    //       Case c = mapCaseInfoWithCase.get(existingCaseInfo);
    //       c.AccountId.addError('Doublon - ne doit pas être inséré');
    //     }
    //   }
    //   System.debug('### TR005 - preventDuplicateCreation - END');
    // }
    
    //ASC MCOSF-1002 - Contrôle sur le type d'équipement actuel et proposé sur la création d'une demande de devis et pose
    public static void preventDuplicateDevisPoseAssetCreation(List<Case> newCases, Boolean isAdmin) {
        
        System.debug('### TR005 - preventDuplicateDevisPoseAssetCreation - BEGIN');
        
        Set<Id> accountsIdSet = new Set<Id>();
        Set<Id> assetsIdSet = new Set<Id>();
        Map<String, Case> mapCaseInfoWithCase = new Map<String, Case>();
        List<String> lstFinishedStatus = new List<String>{'Terminé', 'Annulé (Client)', 'Annulé (Interne)', 'Annulée'};
            
            for (Case c : newCases) {
                String caseInfo = String.valueOf(c.AccountId) + c.Type + String.valueOf(c.AssetId) + c.Type_equipement_propose__c;
                if (c.Type == Label.TypeDemandePoseEquipement && mapCaseInfoWithCase.get(caseInfo) == null) {
                    accountsIdSet.add(c.AccountId);
                    assetsIdSet.add(c.AssetId);
                    mapCaseInfoWithCase.put(caseInfo, c);
                }
            }
        
        //MCOSF-5492 : The SOQL executes under conditions. Not necessary to group it, since it .
        if (mapCaseInfoWithCase.size() > 0) {
            for (Case existingCase : [SELECT Id, AccountId, AssetId, Type_equipement_propose__c, Type FROM Case WHERE AccountId IN :accountsIdSet
                                      AND AssetId IN :assetsIdSet AND Type = :Label.TypeDemandePoseEquipement AND Status NOT IN :lstFinishedStatus]) {
                                          String caseInfo = String.valueOf(existingCase.AccountId) + existingCase.Type + String.valueOf(existingCase.AssetId) + existingCase.Type_equipement_propose__c;
                                          if (!Test.isRunningTest() && !isAdmin && mapCaseInfoWithCase.get(caseInfo) != null) {
                                              Case c = mapCaseInfoWithCase.get(caseInfo);
                                              c.AccountId.addError('TEP Doublon - ne doit pas être inséré');
                                          }
                                      }
        }
        System.debug('### TR005 - preventDuplicateDevisPoseAssetCreation - END');
    }
    
    // Fonction qui permet de mettre à jour le propriétaire des opportunités lorsqu'une demande de type Pose Equipement est
    // mise à jour par un utilisateur dont le rôle n'est pas CRC Quimper
    // ASC - MCOSF-897 - 2021-06-08: Exclut les opportunity de record type: Appareil_Agence_Digitale
    public static void updateOwnerOpportunities(Map<Id, Case> p_map_oldCases, Map<Id, Case> p_map_newCases) {
        System.debug('EDER Debug users : ' + usersMap);
        // Useless, firstRunMajOppOwner is never set false.
        // if (!firstRunMajOppOwner && !Test.isRunningTest()) {
        //   return;
        // }
        
        // firstRunMajOppOwner = true;
        // Map<Id, Id> map_CaseId_UserId = new Map<Id, Id>();
        // Map<Id, Id> map_CaseId_NewUserId = new Map<Id, Id>();
        //MCOSF-5492 : Ajout d'un Set<Id> pour éviter la double SOQL
        Set<Id> oldOwnerIds = new Set<Id>();
        Set<Id> newOwnerIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        for (Id lv_caseId : p_map_oldCases.keySet()) {
            // map_CaseId_UserId.put(lv_caseId, p_map_oldCases.get(lv_caseId).OwnerId);
            // map_CaseId_NewUserId.put(lv_caseId,p_map_newCases.get(lv_caseId).OwnerId);
            oldOwnerIds.add(p_map_oldCases.get(lv_caseId).OwnerId);
            newOwnerIds.add(p_map_newCases.get(lv_caseId).OwnerId);
            ownerIds.addAll(oldOwnerIds);
            ownerIds.addAll(newOwnerIds);
        }
        // System.debug('$$$ map_CaseId_UserId > ' + map_CaseId_UserId);
        
        // Récupération des informations des utilisateurs
        
        // MCOSF-5492 : Only one SOQL needed.
        // Map<Id, User> map_userId_user = new Map<Id, User>([SELECT Id, UserRole.DeveloperName FROM User WHERE Id IN :map_CaseId_UserId.values()]);
        // Map<Id, User> map_userId_newUser = new Map<Id, User>([SELECT Id, UserRole.DeveloperName FROM User WHERE Id IN :map_CaseId_NewUserId.values()]);    
        
        Map<Id, User> map_userId_oldUser = new Map<Id, User>();
        Map<Id, User> map_userId_newUser = new Map<Id, User>();
        
        // List<User> owners = [SELECT Id, UserRole.DeveloperName FROM User WHERE Id IN :ownerIds];
        
        List<User> owners = new List<User>();
        for(Id ownerId: ownerIds){
            
            // for(User owner : owners){
            if(!map_userId_oldUser.containsKey(usersMap.get(ownerId)?.Id) && oldOwnerIds.contains(ownerId)){
                map_userId_oldUser.put(ownerId, usersMap.get(ownerId));
            }
            if(!map_userId_newUser.containsKey(ownerId) && newOwnerIds.contains(ownerId)){
                map_userId_newUser.put(ownerId, usersMap.get(ownerId));
            }
        }
        
        // Détection des demandes de type Pose Equipement dont le rôle du Owner est différent de CRC Quimper
        List<Id> lst_casesForOpportunitieTosUpdate = new List<Id>();
        for (Case lv_case : p_map_oldCases.values()) {
            // Si l'ancien propriétaire de la demande possède un rôle différent de CRC_Quimper alors je garde son identifiant
            // Ne garder que les demandes de type Pose Equipement
            if (map_userId_oldUser.get(lv_case.OwnerId) != null && map_userId_oldUser.get(lv_case.OwnerId).UserRole.DeveloperName != 'CRCQuimper'
                && p_map_oldCases.get(lv_case.Id).RecordTypeId ==CASE_RECORDTYPE_POSEEQUIPEMENT_ID && !map_userId_newUser.values().isEmpty()) {
                    lst_casesForOpportunitieTosUpdate.add(lv_case.Id);
                }
        }
        
        if (!lst_casesForOpportunitieTosUpdate.isEmpty()) {
            List<Opportunity> lst_opportunities = [SELECT Id, OwnerId, Demande__c FROM Opportunity WHERE Demande__c IN :lst_casesForOpportunitieTosUpdate
                                                   AND RecordType.DeveloperName != 'Appareil_Agence_Digitale'];
            System.debug('$$$ lst_opportunities > ' + lst_opportunities);
            for (Opportunity lv_opp : lst_opportunities) {
                String ownerId = p_map_newCases.get(lv_opp.Demande__c).OwnerId;
                if(ownerId.startsWith('005')/* && lv_opp.OwnerId != ownerId*/){
                    // lv_opp.OwnerId = p_map_newCases.get(lv_opp.Demande__c).OwnerId;
                    lv_opp.OwnerId = ownerId;
                }
            }
            
            if (!lst_opportunities.isEmpty()) {
                update lst_opportunities;
            }
        }
    }
    
    // Calculer le nombre de 'Réclamations' dans chmps TECH et date du plus ancien 12 mois
    public static void calculNombreReclamations(List<Case> cases) {
        System.debug('### Calcul nomber of reclamation start ###');
        
        Set<Id> accId = new Set<Id>();
        
        for (Case c : cases) {
            if (c.AccountId != null && c.Type == 'Réclamation') {
                accId.add(c.AccountId);
            }
        }
        
        if (accId != null && accId.size() > 0) {
            List<Account> lstAccount = new List<Account>();
            
            for (Account[] acc : [SELECT Id, TECH_NombreReclamation__c, 
                                  (SELECT Id FROM Cases WHERE Type = 'Réclamation' AND CreatedDate = LAST_N_DAYS:365 )
                                  FROM Account WHERE Id IN :accId]) {
                                      for (Account a : acc) {
                                          // ajouter le nombre de a à un nouveau champ
                                          a.TECH_NombreReclamation__c = a.Cases.size();
                                          lstAccount.add(a);
                                      }
                                  }
            if(lstAccount.size() > 0){
                update lstAccount;
            }
        }
    }
    
    //MCOSF-1945 : Refonte des Process Builder Demande_PB010_MAJ_CaseOwner et Demandes_PB011_MAJCaseOwnerEquipe
    public static void majCaseOwner(Map<Id, Case> cases, Map<Id, Case> oldMap, Boolean isAfter) {
        System.debug('### START majCaseOwner ###');
        if (!isAfter) {
            if (!firstRunMajCaseOwner) {
                return;
            }
            firstRunMajCaseOwner = false;
            
            Set<Id> lastModifiedSetId = new Set<Id>();
            // mia MCO 1089 - Parcours de depannage - MV
            for (Case cs : cases.values()) {
                lastModifiedSetId.add(cs.LastModifiedById);
            }
            
            // User u = [SELECT Username, IDGazelleAgence__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            User u = usersMap.get(UserInfo.getUserId());
            
            for (Case c : cases.values()) {
                if ((c.CreatedById == Label.CL_USER_EXTERNAL_SUPPORT_ID && (c.InformationCRC__c != '' &&
                                                                           (oldMap.get(c.Id).InformationCRC__c == null || oldMap.get(c.Id).InformationCRC__c == ''))) ||
                                                                           (c.InformationCRC__c != oldMap.get(c.Id).InformationCRC__c && c.InformationCRC__c == 'Pas de disponibilité d\'agenda')){
                                                                               System.debug('### majCaseOwner : External Support Service ###');
                                                                               c.OwnerId = Label.CLQueueID;
                                                                           } 
                else if ((c.ChoixAgence__c == oldMap.get(c.Id).ChoixAgence__c || c.SiteDeCreation__c == 'CRC-COMDATA-Service client-Valenciennes') &&
                         u?.Username.left(14) != Label.CLBoomiUsername14characters && u?.Username.left(14) != Label.CLoptitimeUsername14characters) {
                             System.debug('### majCaseOwner : 2 ###');
                             if (u.IDGazelleAgence__c != 'CRC' && c.OwnerId == Label.CLQueueID) {
                                 System.debug('### majCaseOwner : 3 ###');
                                 c.OwnerId = u.Id;
                             } 
                             else if (u.IDGazelleAgence__c == 'CRC' &&  c.OwnerId != Label.CLQueueID && c.OwnerId != Label.CLTeleventeID && c.TECH_RDVProgramme__c == false && c.AssetId == oldMap.get(c.Id).AssetId) {
                                 system.debug('### majCaseOwner : 4 ###');
                                 c.OwnerId = Label.CLQueueID;
                             }
                         } 
                else if ((c.TECH_RDVProgramme__c == true || (c.TECH_NombreRDVConfirme__c > 0 && (u.Username == Label.CLboomiUsername || u.Username == Label.CLoptitimeUsername))) &&
                         c.OwnerId == Label.CLQueueID && c.AssetId == oldMap.get(c.Id).AssetId && c.InformationCRC__c == 'Pas de disponibilité d\'agenda') {
                             system.debug('### majCaseOwner : 5 ###');
                             c.OwnerId = Label.CL_QueueId_BacklogNonSuivi;
                         }
            }
        }
        //MCOSF-2573 : maj case owner after update - START
        else {
            if (!firstRunMajCaseOwnerAfterUpdate) {
                return;
            }
            firstRunMajCaseOwnerAfterUpdate = false;
            
            Set<String> typeDemande = new Set<String>{'Dépannage', 'Pose d\'équipement', 'Travaux', 'Mise en service', 'Visite / Entretien'};
            Set<String>  excludedUserIds = new Set<String>{Label.CLBoomiUsername14characters, Label.CLoptitimeUsername14characters}; // Trouver les Labels des Ids des users
            Set<String> woStatuses = new Set<String>{'102', '105'};
                
            // List<WorkOrder> wos = [SELECT Id, CaseId, Case.LastModifiedById, Case.ChoixAgence__c, Case.SiteDeCreation__c FROM WorkOrder 
            //                       WHERE CaseId IN :cases AND Status IN :woStatuses AND Case.Type IN :typeDemande AND Case.LastModifiedById NOT IN :excludedUserIds 
            //                       AND Case.lastModifiedBy.IDGazelleAgence__c != 'CRC'];
            
            // List<Case> caseToUpdate = new List<Case>();
            
            //MCOSF-5492 : 
            // En after update a cause des flows ?
            
            for (WorkOrder wo : relatedWos) {
                // relatedWos can contain WOs on daughter cases. Therefore we must check them
                if (cases.containsKey(wo.CaseId) && cases.get(wo.CaseId)?.OwnerId != oldMap.get(wo.CaseId)?.OwnerId 
                    && woStatuses.contains(wo.Status) && typeDemande.contains(cases.get(wo.CaseId).Type) && 
                    !excludedUserIds.contains(usersMap.get(UserInfo.getUserId()).Username.left(14)) && 
                    usersMap.get(UserInfo.getUserId()).IdGazelleAgence__c != 'CRC' && cases.get(wo.CaseId).OwnerId == Label.CLQueueID && cases.get(wo.CaseId).InformationCRC__c != 'Pas de disponibilité d\'agenda' &&
                    (cases.get(wo.CaseId).ChoixAgence__c == oldMap.get(wo.CaseId).ChoixAgence__c || cases.get(wo.CaseId).SiteDeCreation__c =='CRC-COMDATA-Service client-Valenciennes')) {
                        // We are after update. We need a new Case instance to avoid an error on update.
                        casesToUpdateMap.put(wo.CaseId, new Case(Id = wo.CaseId, OwnerId = UserInfo.getUserId()));
                }
            }
        // if (caseToUpdate.size() > 0) {
        //   update caseToUpdate;
        // }
        }
        //MCOSF-2573 : maj case owner after update - END
        system.debug('### END majCaseOwner ###');
    }
    
    //MCOSF-4744 START
    public static void majGestionaireDemande(List<Case> cases){
        Set<String> caseType = new Set<String>{'Souscription','Résiliation','Information','Réclamation'};
            // List<Case> newCaseList=[Select id,Type,OwnerId from Case where id IN: cases];
            // List<Case> casesToUpdate = new List<Case>();
            // User u = [SELECT Username, IDGazelleAgence__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            User u = usersMap.get(UserInfo.getUserId());
        
        for(Case newCase: cases){
            if(u.IdGazelleAgence__c == 'CRC' && caseType.contains(newCase.Type) && newCase.OwnerId != Label.CLQueueID){
                casesToUpdateMap.put(newCase.Id, new Case(Id = newCase.Id, OwnerId=Label.CLQueueID));
            }
        }
        // if(casesToUpdateMap.size()>0){
        //     update casesToUpdateMap;
        // }
    }
    //MCOSF-4744 END
    
    //MCOSF-1945 : Refonte du Process Builder REQ_PB004_CreerUneDemandeDepuisEquipementOuDemande
    public static void majSiteDeRattachement(List<Case> cases, Map<Id, Case> newCasesMap) {
        System.debug('### START majSiteDeRattachement ###');
        if (!firstRunMajSiteDeRattachement) {
            return;
        }
        firstRunMajSiteDeRattachement = false;
        
        Set<Id> assetIds = new Set<Id>();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> contractIds = new Set<Id>();
        for (Case c : cases) {
            contractIds.add(c.ServiceContract__c);
            assetIds.add(c.AssetId);
            assetIds.add(c.Parent?.AssetId);
            parentIds.add(c.ParentId);
        }
        // contractIds.remove(null);
        Map<Id, ServiceContract> scMap = new Map<Id, ServiceContract>([SELECT Id, RecordType.Name FROM ServiceContract WHERE Id IN :contractIds]);
        // Map<Id, Asset> assetMap = new Map<Id, Asset>([ SELECT Id, Site__c, ProduitGeneriqueFonction__c FROM Asset WHERE Id IN :assetIds]);
        // Map<Id, Case> parentMap = new Map<Id, Case>([SELECT Id, SiteDeRattachement__c, AssetId FROM Case WHERE Id IN :parentIds]);
        
        for (Case caseUpdated : cases) {
            caseUpdated.SiteDeRattachement__c = astMap.get(caseUpdated.assetId)?.Site__c; // MCOSF-6426 : retrieve "SiteDeRattachement__c" value directly from the Asset Site__c field instead of looking to the parent case "SiteDeRattachement__c" if updating a case with parentId != null
            caseUpdated.TECH_CodeEquipement__c = astMap.get(parentCasesMap.get(caseUpdated?.ParentId)?.assetId)?.ProduitGeneriqueFonction__c ?? astMap.get(caseUpdated.assetId).ProduitGeneriqueFonction__c;
            caseUpdated.TECH_ClientTypeFromContract__c = (scMap.get(caseUpdated.ServiceContract__c) == null) ? 'IND HC' :
            (scMap.get(caseUpdated.ServiceContract__c).RecordType.Name == 'Contrat Collectif') ? 'COLL' : 'IND SC';
        }
        System.debug('### END majSiteDeRattachement ###');
    }
    
    //MCOSF-1945 :Refonte du Process Builder REQ_PB010_DepEnLigneChangeOfSite
    public static void majSiteGestionnaire(List<Case> cases) {
        System.debug('### START majSiteGestionnaire ###');
        if (!firstRunMajSiteGestionnaire) {
            return;
        }
        firstRunMajSiteGestionnaire = false;
        // Map<Id, Asset> mapAssets = new Map<Id, Asset>();
        Set<Id> assetIds = new Set<Id>();
        for (Case c : cases) {
            assetIds.add(c.AssetId);
        }
        if (!assetIds.isEmpty()) {
            // mapAssets = new Map<Id, Asset>([SELECT Id, Site__c FROM Asset WHERE Id IN :assetIds]);
        }
        for (Case caseUpdated : cases) {
            if (caseUpdated.Resultat_depannage_en_ligne__c != 'Echec' && caseUpdated.Resultat_depannage_en_ligne__c != 'Hors cible'
               ) {
                   caseUpdated.ChoixAgence__c = Label.CRC_DEL;
               } 
            else if (caseUpdated.ChoixAgence__c != astMap.get(caseUpdated.AssetId).Site__c) {
                caseUpdated.ChoixAgence__c = astMap.get(caseUpdated.AssetId).Site__c;
            }
        }
        System.debug('### END majSiteGestionnaire ###');
    }
    
    //MCOSF-2103 VD
    public static void majChampsMotifARevoirLastModifiedDate(List<Case> ca, Map<Id, Case> oldCaMap) {
        for (Case caseToUpdate : ca) {
            if (caseToUpdate.MotifARevoir__c != oldCaMap.get(caseToUpdate.Id).MotifARevoir__c) {
                caseToUpdate.MotifARevoirLastModifiedDate__c = DateTime.now();
            }
        }
    }
    
    //MCOSF-2382 ASC
    public static void flagCaseAsReattribuee(List<Case> cases, Map<Id, Case> oldCasesMap) {
        if (!firstRunflagCaseAsReattribuee && !Test.isRunningTest()) {
            return;
        }
        
        // User u = [SELECT IsAdmin__c FROM User WHERE Id = :UserInfo.getUserId()];
        
        User u = usersMap.get(UserInfo.getUserId());
        
        for (Case ca : cases) {
            if (ca.OwnerId != oldCasesMap.get(ca.Id).OwnerId && ca.LastModifiedById != ca.OwnerId && !u.IsAdmin__c) {
                ca.Reattribuee__c = true;
            } 
            else if (ca.LastModifiedById == ca.OwnerId) {
                ca.Reattribuee__c = false;
            }
        }
    }
    
    /*public static void checkUrgenceTechniqueField(List<Case> newCases, Map<Id, Case> oldCaseMap) { // added for MCOSF-6272 -- pass to true UrgenceTechnique field value if InformationCRC value is one of the targetValues of the set inside the method
        Set<String> targetValues = new Set<String>{'Urgence technique Trans. Agence', 'UT HO Appel OK NºUrgence technique Agence', 'UT HO Appel KO NºUrgence technique Agence'};

        for (Case c : newCases) {
            if (oldCaseMap != null) { // Before Update    
                Case oldCase = oldCaseMap.get(c.Id);
                if (c.InformationCRC__c != oldCase.InformationCRC__c) {
                    if (targetValues.contains(c.InformationCRC__c)) {
                        c.UrgenceTechnique__c = true;}
                }
            }
            else { // Before Insert 
                if (targetValues.contains(c.InformationCRC__c)) {
                    c.UrgenceTechnique__c = true;}
            }
        }
    }*/

    // MCOSF-2643 - Service Client : Echange client lors de la creation d'une demande de depannage depuis l'espace client - START
    public static void createTaskFromCaseEC(List<Case> demande) {
        if (!firstRuncreateTaskFromCaseEC) {
            return;
        }
        firstRuncreateTaskFromCaseEC = false;
        
        List<Task> taskToCreate = new List<Task>();
        
        for (Case demList : demande) {
            if (demList.Origin == Label.CLCaseOrigin || demList.Origin == 'Site web') {
                Task newTask = new Task();
                newTask.RecordTypeId = Schema.SObjectType.Task.getRecordTypeInfosByName().get('Interactions').getRecordTypeId();
                newTask.WhoId = demList.ContactId;
                newTask.ActivityDate = date.Today();
                newTask.Account__c = demList.AccountId;
                newTask.Subject = (demList.Origin == Label.CLCaseOrigin) ? 'Canal Espace Client' : 'Canal Site Web';
                newTask.Type = 'Interaction entrante';
                newTask.Priority = 'Normale';
                newTask.Status = 'Achevée';
                newTask.WhatId = demList.Id;
                newTask.Description = demList.Subject;
                taskToCreate.add(newTask);
            }
        }
        if (taskToCreate.size() > 0) {
            insert taskToCreate;
        }
    }
    
    public static void deleteRIB(List<Case> cases) {
        List<Id> caseIds = new List<Id>();
        Map<Id, Id> casesAndContacts = new Map <Id, Id> (); // Addedfor MCOSF-5260
        for (Case c : cases) {
            caseIds.add(c.Id);
            casesAndContacts.put(c.Id, c.ContactId); // Addedfor MCOSF-5260
        }
        
        // Suppression des pièces jointe
        List<ContentDocumentLink> cdls = [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :caseIds];
        if (cdls.size() > 0) {
            List<Id> ids = new List<Id>();
            for (ContentDocumentLink cdl : cdls) {
                ids.add(cdl.ContentDocumentId);
            }
            List<ContentDocument> cds = [SELECT Id FROM ContentDocument WHERE Id IN :ids ];
            
            if (cds.size() > 0) {
                //try{delete cds;}catch(Exception e) {return;}
                List<Database.DeleteResult> lstResults = Database.delete(cds, false);
                for (Integer i = 0; i < lstResults.size(); i++) {
                    if (!lstResults[i].isSuccess()) {
                        cds[i].addError(lstResults[i].getErrors()[0].getStatusCode() + ' - ' + lstResults[i].getErrors()[0].getMessage());
                    }
                }
                //start Addedfor MCOSF-5260
                // Création de l'échange client (l'email est envoyé via le workflow SC_WF001_Email_Mensualisation)
                List<Task> tasksToCreate = new List<Task>();
                for(Id caseId : casesAndContacts.keySet()) {
                    Task echange = new Task();
                    echange.Subject = Label.Brand_Name + ' : mise en place du prélèvement mensuel de votre contrat.';
                    echange.Status = 'Achevée';
                    echange.WhatId = caseId;
                    echange.WhoId = casesAndContacts.get(caseId);
                    echange.Type = 'Interaction sortante';
                    echange.ActivityDate = Date.today();
                    tasksToCreate.add(echange);
                }
                //try{insert tasksToCreate;}catch(Exception e) {return;}
                List<Database.SaveResult> lstResults2 = Database.insert(tasksToCreate, false);
                for(Integer i=0; i< lstResults2.size(); i++){
                    if (!lstResults2[i].isSuccess()) {
                        tasksToCreate[i].addError(lstResults2[i].getErrors()[0].getStatusCode() + ' - ' + lstResults2[i].getErrors()[0].getMessage());
                    }
                }
                //end Addedfor MCOSF-5260
            }
        }
    }
    
    //MCOSF-2575 : Guepard - parcours tél - rétractation client - START
    public static void majCaseOwnerIdCSP(List<Case> demList, Map<Id, Case> oldDemMap) {
        List<Group> groups = [SELECT Id, Name FROM Group WHERE Name IN ('CSP', 'Equipe Demandes courantes') AND Type = 'Queue'];
        
        String cspId;
        String edcId;
        
        for(Group g : groups){
            if(g.Name == 'CSP'){
                cspId = g.Name;
            }
            if(g.Name == 'Equipe Demandes courantes'){
                edcId = g.Name;
            }
        }
        // List<Group> groupCSPList = [SELECT Id, Name FROM Group WHERE Name = 'CSP' AND Type = 'Queue' LIMIT 1];
        // List<Group> groupEDCList = [SELECT Id, Name FROM Group WHERE Name = 'Equipe Demandes courantes' AND Type = 'Queue' LIMIT 1];
        
        for (Case demande : demList) {
            if (demande.Type == 'Résiliation' && demande.MotifResiliation__c == 'Rétractation' && demande.ChoixAgence__c != oldDemMap.get(demande.Id).ChoixAgence__c) {
                demande.OwnerId = (demande.TECH_IDSiteGestionnaire__c == 'CSP-COMPTA-CLIENT') ? cspId : edcId;
            }
        }
    }
    
    public static void envoiEmailSiteGestionnaireCSP(List<Case> demList, Map<Id, Case> oldDemMap) {
        for (Case demande : demList) {
            List<String> recipientEmails = new List<String>();
            recipientEmails.addAll((Label.CSP_EMAIL).split(';'));
            String orgURL = Label.ORG_URL;
            String subject = 'Remboursement à traiter - ' + demande.TECH_SiteGes_NomSiteParent__c;
            String emailBody = '<p>Remboursememt client à traiter, suite à rétractation ou résolution du contrat (Clauses de résolution des CGE) : ';
            emailBody += '<b><a href="' + orgURL + '/lightning/r/Case/' + demande.Id + '/view" target="_blank">' + demande.CaseNumber + '</a></b></p>';
            emailBody +=' <p>Un avoir a été généré automatiquement. Le remboursement porte sur la totalité des sommes encaissées au titre de ce contrat.</p>';
            emailBody += '<p>Consulter la vue de liste  « CSP-Remboursement à traiter »</p>';
            
            if (
                demande.Type == 'Résiliation' &&
                demande.MotifResiliation__c == 'Rétractation' &&
                demande.ChoixAgence__c != oldDemMap.get(demande.Id).ChoixAgence__c &&
                demande.TECH_IDSiteGestionnaire__c == 'CSP-COMPTA-CLIENT'
            ) {
                Messaging.SingleEmailMessage singleEmail = new Messaging.SingleEmailMessage();
                
                singleEmail.setToAddresses(recipientEmails);
                singleEmail.setReplyTo(Label.EmailAddress_NoReply);
                singleEmail.setSenderDisplayName(Label.EmailAddress_NoReply);
                singleEmail.setSubject(subject);
                singleEmail.setHtmlBody(emailBody);
                
                Messaging.SendEmailResult[] results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ singleEmail }
                );
                
                for (Messaging.SendEmailResult result : results) {
                    if (result.isSuccess()) {
                        System.debug('Single Email sent successfully');
                    } else {
                        System.debug('Single Email send failed');
                    }
                }
            }
        }
    }
    //MCOSF-2575: Guepard - parcours tél - rétractation client - END

    /*
    public static void updateWosNewParentCases(Map<String, WorkOrder> gzlIdMapWoWithoutCase, List<Case> newCases){

        // Set<Id> caseIds

        // MCOSF-6282 : Changes of the related case that otherwise occur after insert are reported here.

        // Adaptation of AP_CloseCaseDepVeAutomatic.updateCases

        for(Case c: newCases){

            List<String> customTypes = new List<String>{'10003', '10004', '10005'}; 
            List<String> statuses = new List<String>{'51', '110', '101', '108', '104', '106'};

            WorkOrder myWorkOrder = gzlIdMapWoWithoutCase.get(c.TECH_IdGzlOfFirstWO__c);

            if(customTypes.contains(myWorkOrder.Type__c) && statuses.contains(myWorkOrder.Status)){
                c.TECH_IsWOARevoir__c = (myWorkOrder.Status == '51');
                c.TECH_RecentWODate__c = (myWorkOrder.StartDate !=  null && myWorkOrder.Status != '51') ? myWorkOrder.StartDate : myWorkOrder.DateDebutProgrammee__c;
                c.TECH_RecentWOARevoirDate__c = (myWorkOrder.StartDate !=  null && myWorkOrder.Status == '51') ? myWorkOrder.StartDate : myWorkOrder.DateDebutProgrammee__c;
            }

            // Adaptation of AP_UpdateCasesFromWorkOrderHandler.countTECHNb_BIStatus_FieldsValue

            switch on myWorkOrder.Status {
                when '1' {
                    c.TECH_NombreRDVCree__c = 1;
                }
                when '102' {
                    c.TECH_NombreRDVProgramme__c = 1;
                }
                when '103' {
                    c.TECH_NombreRDVAvise__c = 1;
                }
                when '104' {
                    c.TECH_NombreRDVReportClient__c = 1;
                }
                when '105' {
                    c.TECH_NombreRDVConfirme__c = 1;
                }
                when '106' {
                    c.TECH_NombreRDVReportEHS__c = 1;
                }
                when '2' {
                    c.TECH_NombreRDVRealise__c = 1;
                }
                when else {
                    continue;
                }
            }

            //AP_updateCaseInfoCRC skipped because it should always be created by Gazelle

            // Set<String> userIds = new Set<String>{Label.CL_USER_GAZELLE_ID_15D, Label.CL_USER_JUMANJI_ID, Label.CL_USER_NUM_CE_ID, Label.CL_USER_OPTITIME_ID};
            // if(!userIds.contains(String.valueOf(myWorkOrder.CreatedById).substring (0,15)) && !userIds.contains(String.valueOf(myWorkOrder.LastModifiedById).substring(0,15))){
            //     c.InformationCRC__c = (myWorkOrder.Information_CRC__c == '--aucun--') ? '' : myWorkOrder.Information_CRC__c;
            //     c.OwnerId = Label.CLQueueID; // Added for MCOSF-3327
            // }

            // TR008_WorkOrderTriggerHandler.afterInsertProcessing

            c.ArevoirDateProchaineIntervention__c = myWorkOrder.DateDebutProgrammee__c;

            // AP_WorkOrderPresenceInterventionHandler.updateTECH_Intervention
            
            c.TECH_InterventionExiste__c = (c.Status != 'Terminé');

        }
    }*/
  }
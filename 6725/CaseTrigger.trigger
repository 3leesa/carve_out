/*--------------------------------------------------------------------------------------------------------------------------
Author: Unknown
Company: Unknown
Description: Trigger du case
History: 
<XX/XX/XXXX> <Unknown> <Unknown> <XXX> Création
<09/04/2025> <Sprint 74> <MCOSF-5492> <EDE> <Optimisation du trigger Case, suppression des SOQL et ajout d'une Map<Id, Asset> à la signature>
<05/12/2025> <Sprint 84> <MCOSF-6327> <EDE> <Optimisation des perfs : suppression de l'appel à AP_FillServiceContractIntent.createCasesIntent>
--------------------------------------------------------------------------------------------------------------------------*/
trigger CaseTrigger on Case (before insert, before update, after insert, after update, before delete, after delete) {
    System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- BEGIN');

    Id ExtUserProfileId = Label.ExternalUserProfileId;
    CS001_NeutraliserRegles__c cs = CS001_NeutraliserRegles__c.getInstance();    
    if(cs.TECH_NeutraliserTrigger__c){return;}
    
    Boolean isExtUserProfile = (UserInfo.getProfileId() == ExtUserProfileId); //NI : MCOSF-2742 - 28/03/2023
    Map<Id, Case> newCasesMap = (Map<Id, Case>) Trigger.newMap;
    Map<Id, Case> oldCasesMap = (Map<Id, Case>) Trigger.oldMap;

    List<Case> newCases = (List<Case>) Trigger.new;
    List<Case> oldCases = (List<Case>) Trigger.old;
    
    if (Trigger.isBefore) {
        TR005_CaseTriggerHandler.getRelatedRecords(newCases, oldCasesMap);
        if (Trigger.isInsert) {
            User u = [SELECT IsAdmin__c from User where Id = :UserInfo.getUserId()];
            System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- Before Insert -- BEGIN');
            // TR005_CaseTriggerHandler.preventDuplicateCreation(newCases, u.IsAdmin__c);
            TR005_CaseTriggerHandler.preventDuplicateDevisPoseAssetCreation(newCases, u.IsAdmin__c);
            
            //Send list of cases before insertion in salesforce for processing. 
            AP_createCasesWithSites.createCasesSiteTechId(newCases, TR005_CaseTriggerHandler.sitesMap);

            //Refactoring for Intent 3F Cases.
            // MCOSF-6327 : deactivation
            // AP_FillServiceContractIntent.createCasesIntent(newCases, TR005_CaseTriggerHandler.astMap);
            
            List<Case> lstVillogiaCase = new List<Case>();
            List<Case> lstCaseWithoutContract = new List<Case>();
            List<Case> lstMajSiteGestionnaire = new List<Case>();
            for(Case caseRecord : newCases) {
                if(String.isNotBlank(caseRecord.TECH_PhenixId__c)){
                    lstVillogiaCase.add(caseRecord);
                }
                if(String.isBlank(caseRecord.ServiceContract__c)){
                    lstCaseWithoutContract.add(caseRecord);
                }
                if(caseRecord.Type == 'Dépannage' && !String.isBlank(caseRecord.Besoin_d_assistance__c) && caseRecord.Status != 'Terminé' && 
                    (caseRecord.Resultat_depannage_en_ligne__c == 'Echec' || caseRecord.Resultat_depannage_en_ligne__c == 'Hors cible' ||
                    (caseRecord.Resultat_depannage_en_ligne__c == 'Assistance client réussie' && caseRecord.TECH_InterventionExiste__c) || 
                    (caseRecord.Resultat_depannage_en_ligne__c == 'Client essaye et rappelle si besoin' && caseRecord.TECH_InterventionExiste__c)||
                    ((caseRecord.Status == 'Nouveau' || caseRecord.Status == 'En cours') && caseRecord.ChoixAgence__c != 'a011p00001PfVyyAAF' && 
                    !caseRecord.TECH_CreatedBySelfHelp__c))) {
                    lstMajSiteGestionnaire.add(caseRecord);
                }
            }

            //Send list of Villogia cases before creating them in Salesforce for processing.
            if(lstVillogiaCase.size() > 0){
                AP_createCasesVillogia.fillAccountToCases(lstVillogiaCase, TR005_CaseTriggerHandler.astMap);
            }

            //Send Cases without service contract for further processing.
            if(lstCaseWithoutContract.size() > 0){
                AP_FillCaseWithContract.fillContractID(lstCaseWithoutContract);
            }

            //Send Cases from lstMajSiteGestionnaire for further processing.
            if(lstMajSiteGestionnaire.size() > 0){
                TR005_CaseTriggerHandler.majSiteGestionnaire(lstMajSiteGestionnaire);
            }

            //TR005_CaseTriggerHandler.beforeInsertProcessingDemandeUrgente(newCases); // added for MCOSF-6272
            System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- Before Insert -- END');
        }

        // MCOSF-2742 - bypass update for community user
        // MCOSF-2806 - don't exclude community users for beforeUpdateProcessing
        if (Trigger.isUpdate) {
            System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- Before Update -- BEGIN');
            TR005_CaseTriggerHandler.beforeUpdateProcessing(newCases);
            TR005_CaseTriggerHandler.eContrat_afterProcessing(newCases);
            if (!isExtUserProfile) {
                TR005_CaseTriggerHandler.CMI_beforeUpdateProcessing(newCases, oldCasesMap, newCasesMap);
                Map<Id, Case> majCaseOwnerLst = new Map<Id, Case>();
                List<Case> lstMajSiteRattachement = new List<Case>();
                List<Case> lstMajSiteGestionnaire = new List<Case>();
                Set<String> closedStatuses = new Set<String>{'Terminé', 'Annulé (Client)', 'Annulé (Interne)'};
                Set<String> excludedTypes = new Set<String>{'Réclamation', 'Résiliation', 'Souscription'};
                for(Case c : newCases) {
                    if(!closedStatuses.contains(c.Status) && !excludedTypes.contains(c.Type)) {
                        majCaseOwnerLst.put(c.Id, c);
                    }
                    if(String.isBlank(c.SiteDeRattachement__c) && String.isNotBlank(c.AssetId)) {
                        lstMajSiteRattachement.add(c);
                    }
                    if(c.Type == 'Dépannage' && !String.isBlank(c.Besoin_d_assistance__c) && c.Status != 'Terminé' &&
                    (c.Resultat_depannage_en_ligne__c == 'Echec' || c.Resultat_depannage_en_ligne__c == 'Hors cible' || 
                    (c.Resultat_depannage_en_ligne__c == 'Assistance client réussie' && c.TECH_InterventionExiste__c)|| 
                    (c.Resultat_depannage_en_ligne__c == 'Client essaye et rappelle si besoin' && c.TECH_InterventionExiste__c)|| 
                    ((c.Status == 'Nouveau' || c.Status == 'En cours') && c.ChoixAgence__c != Label.CRC_DEL && !c.TECH_CreatedBySelfHelp__c))) {
                        lstMajSiteGestionnaire.add(c);
                    }
                }
    
                if(majCaseOwnerLst.size() > 0 && UserInfo.getLastName() !='Gazelle') {
                    TR005_CaseTriggerHandler.majCaseOwner(majCaseOwnerLst, oldCasesMap, Trigger.isAfter); // Commneted for MCOSF-6000
                }
    
                //Send Cases without SiteDeRattachement__c for further processing.
                if(lstMajSiteRattachement.size() > 0){
                    TR005_CaseTriggerHandler.majSiteDeRattachement(lstMajSiteRattachement, newCasesMap);
                }
    
                if(lstMajSiteGestionnaire.size() > 0) {
                    TR005_CaseTriggerHandler.majSiteGestionnaire(lstMajSiteGestionnaire);
                }
    
                TR005_CaseTriggerHandler.majChampsMotifARevoirLastModifiedDate(Trigger.new, Trigger.oldMap); //added MCOSF-2103 VD
                TR005_CaseTriggerHandler.flagCaseAsReattribuee(newCases, oldCasesMap); //MCOSF-2382 ASC

                //MCOSF-2575: Guepard - parcours tél - rétractation client
                TR005_CaseTriggerHandler.majCaseOwnerIdCSP(Trigger.new, Trigger.oldMap);// Commneted for MCOSF-6000
                
                System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- Before Update -- END');
            }
        }
    }
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- After Insert -- BEGIN');
            if(!Test.isRunningTest()) TR005_CaseTriggerHandler.majGestionaireDemande(newCases); //MCOSF-4744
            TR005_CaseTriggerHandler.afterInsertProcessing(newCases);
            TR005_CaseTriggerHandler.eContrat_afterProcessing(newCases);
            //création d'opportunité sur demandes (devis/pose, devis/pose AD, Souscription)
            TR005_CaseTriggerHandler.createOpportunityOnCase(newCases);
            TR005_CaseTriggerHandler.calculNombreReclamations(newCases);
            //MCOSF-2643 - Service Client : Echange client lors de la creation d'une demande de depannage depuis l'espace client
            TR005_CaseTriggerHandler.createTaskFromCaseEC(newCases);
            //MCOSF-6278 -Creates "Prestation Hors Contrat" Opportunity when a "Visite / Entretien" case is created on an Asset with no active contract
            TR005_CaseTriggerHandler.createOppForPrestationHorsContrat(newCases);
            //System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- After Insert -- END');
        }

        // MCOSF-2742 - bypass update for community user
        if (Trigger.isUpdate && !isExtUserProfile) {
            Map<Id, Case> newUpdateOwnerOppMap = new Map<Id, Case>();
            Map<Id, Case> oldUpdateOwnerOppMap = new Map<Id, Case>();
            for(Case c : newCases) {
                if(c.Type == 'Pose d\'équipement'){
                    newUpdateOwnerOppMap.put(c.id, c);
                }
            }
            for(Case c : oldCases) {
                if(c.Type == 'Pose d\'équipement'){
                    oldUpdateOwnerOppMap.put(c.id, c);
                }
            }
            System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- After Update -- BEGIN');
            //TR005_CaseTriggerHandler.CMI_afterProcessing(newCases, 'UPDATE', oldCasesMap);
            // TR005_CaseTriggerHandler.EContrat_afterProcessing(newCases,oldCasesMap,false);
            if(oldUpdateOwnerOppMap.size()>0 && newUpdateOwnerOppMap.size()>0){
              TR005_CaseTriggerHandler.updateOwnerOpportunities(oldCasesMap, newCasesMap);  
            }
            
            // MCOSF-3398 : on supprime les RIB des demandes 'Annulée'
            // MCOSF-6332 : supprime les RIB des demandes 'Terminé' aussi
            List<Case> news = new List<Case>();
            Map<Id, Case> old = new Map<Id, Case>();
            for(Case c : newCases){
                if((c.Status.startsWith('Annulé') || c.Status == 'Terminé') && c.Status != (oldCasesMap.get(c.Id).Status) && 
                c.Type == 'Souscription' && c.Origin == 'Espace Client' && 
                (c.Motif_Souscription__c == 'Modification de mode de paiement' || c.Motif_Souscription__c == 'Mensualisation'))
                {
                    news.add(c);
                }
            }
            if(news.size() > 0){

                //Passer seulement la liste des Ids ?
                TR005_CaseTriggerHandler.deleteRIB(news);
            }

            //MCOSF-2573 : MAJ CaseOwner after update
            
            TR005_CaseTriggerHandler.majCaseOwner(Trigger.newMap, Trigger.oldMap, Trigger.isAfter);// Commneted for MCOSF-6000
            System.debug(LoggingLevel.INFO,'##### Trigger CaseTrigger -- After Update -- END');
            
            //MCOSF-2575: Guepard - parcours tél - rétractation client
            TR005_CaseTriggerHandler.envoiEmailSiteGestionnaireCSP(Trigger.new, Trigger.oldMap);

            //MCOSF-4042 : TR005 : basculer la methode updateRelatedCaseStatusClosed() en after Update
            TR005_CaseTriggerHandler.afterUpdateProcessing(newCases);
        }
        TR005_CaseTriggerHandler.upsertAll();
    }
}
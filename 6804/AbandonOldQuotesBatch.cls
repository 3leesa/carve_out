/*
*** Batch class to close Quotes with inactivity greater then 5 months
*** This batch is intended to replace the flow 'Batch_Quote_Draft_inactivityThreeMonths'
*** Test Class: AbandonOldQuotesBatch_Test
*/
global class AbandonOldQuotesBatch implements Database.Batchable<SObject> {
	 global CS001_NeutraliserRegles__c csBypass = CS001_NeutraliserRegles__c.getInstance(UserInfo.getUserId());
    
     global Database.QueryLocator start(Database.BatchableContext BC) {
         csBypass.TECH_NeutraliserTrigger__c = true;
         csBypass.TECH_NeutraliserProcessBuilder__c = true;
         csBypass.TECH_NeutraliserRegleWorkflow__c = true;
         csBypass.TECH_NeutraliserRegleValidation__c = true;
         update csBypass;
         
        Date thresholdDate = Date.today().addDays(-150);

        return Database.getQueryLocator([
            SELECT Id, SBQQ__Status__c
            FROM SBQQ__Quote__c
            WHERE RecordType.DeveloperName = 'Devis_appareil'
              AND SBQQ__Status__c = 'Draft'
              AND LastModifiedDate < :thresholdDate
        ]);
    }

    global void execute(Database.BatchableContext BC, List<SBQQ__Quote__c> scope) {
        if (scope.isEmpty()) {
            return;
        }
        
        List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();

        for (SBQQ__Quote__c q : scope) {
            q.SBQQ__Status__c = 'Abandoned';
            quotesToUpdate.add(q);
        }

        if (!quotesToUpdate.isEmpty()) {
            Database.update(quotesToUpdate, false);
        }    
    }

    global void finish(Database.BatchableContext BC) {
        System.debug('Batch completed: old quotes updated to Abandoned');
        // Reset bypass
        csBypass.TECH_NeutraliserTrigger__c = false;
        csBypass.TECH_NeutraliserProcessBuilder__c = false;
        csBypass.TECH_NeutraliserRegleWorkflow__c = false;
        csBypass.TECH_NeutraliserRegleValidation__c = false;
        update csBypass;
    }
}
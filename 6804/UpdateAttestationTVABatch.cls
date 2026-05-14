/*
***Description: Batch class to update the field AttestationTVA__c on Logement__c records -> MCOSF-6734
***Test Class: UpdateAttestationTVABatch_Test
*/

public class UpdateAttestationTVABatch implements Database.Batchable<SObject> {

    public CS001_NeutraliserRegles__c csBypass = CS001_NeutraliserRegles__c.getInstance(UserInfo.getUserId());
    private static final String USAGE_HABITAT = 'HABI';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        csBypass.TECH_NeutraliserTrigger__c = true;
        csBypass.TECH_NeutraliserProcessBuilder__c = true;
        csBypass.TECH_NeutraliserRegleWorkflow__c = true;
        csBypass.TECH_NeutraliserRegleValidation__c = true;
        update csBypass;
        
        Date limitDate = Date.today().addMonths(-24);

        // Fetch records that need to be updated to true OR updated to false
        return Database.getQueryLocator([
            SELECT Id, UsageLogement__c, DateFinConstruction__c, AttestationTVA__c
            FROM Logement__c
            WHERE 
                (UsageLogement__c = :USAGE_HABITAT AND (DateFinConstruction__c = null OR DateFinConstruction__c < :limitDate) AND AttestationTVA__c = false)
            OR 
                (UsageLogement__c = :USAGE_HABITAT AND DateFinConstruction__c >= :limitDate AND AttestationTVA__c = true)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Logement__c> scope) {
        Date limitDate = Date.today().addMonths(-24);
        
        for (Logement__c loge : scope) {
            if (loge.UsageLogement__c == USAGE_HABITAT && (loge.DateFinConstruction__c == null || loge.DateFinConstruction__c < limitDate)) {
                loge.AttestationTVA__c = true;
            } 
            else {
                loge.AttestationTVA__c = false;
            }
        }

        if (!scope.isEmpty()) {
            Database.update(scope, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Reset bypass
        csBypass.TECH_NeutraliserTrigger__c = false;
        csBypass.TECH_NeutraliserProcessBuilder__c = false;
        csBypass.TECH_NeutraliserRegleWorkflow__c = false;
        csBypass.TECH_NeutraliserRegleValidation__c = false;
        update csBypass;
    }
}
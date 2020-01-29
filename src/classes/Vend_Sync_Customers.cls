// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend_Sync_DeletedResults.srSyncWebsiteDeletedResults( new List<Id> { '701R00000008JS4' });
*/
//  3) click Execute

global class Vend_Sync_DeletedResults implements Database.Batchable<sObject>, Database.AllowsCallouts { 

    global String query;

    global Database.querylocator start(Database.BatchableContext BC) {
        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_DeletedResults::start - query: ' + query);
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext info, List<sObject> scope) {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_DeletedResults::execute - scope: ' + scope);

        List<Id> campaignIds = new List<Id>();
        for (sObject scopeRecord :scope) {
            campaignIds.add(((Campaign)scopeRecord).Id);
        }

		if (campaignIds.isEmpty()) {
            String errorMessage = '***** Vend_Sync_DeletedResults::execute - No Active Campaign';
            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

			return;
        }

        String campaignId = String.valueOf(campaignIds[0]);
        this.SyncWebsiteDeletedResults(campaignId);
    }

    public void SyncWebsiteDeletedResults(String campaignId) {    

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody('{"token":"' + Vend_Sync_SharedCode.GetExternalWebsiteToken() + '"}');

		List<SR_Result__c> deletedResults = new List<SR_Result__c>();

        Integer queryOffset = 0;
        Integer queryLimit = 100;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 1;
        }

        Map<String,Id> activeTeamResults = Vend_Sync_SharedCode.GetActiveTeamResults(campaignId, String.valueOf(this).substring(0,String.valueOf(this).indexOf(':')));

        while (true) {
            
            String endpoint = 'https://' + Vend_Sync_SharedCode.GetExternalWebsiteSubdomain() + '.studentsrebuild.org/sync/deleted_submissions/' + campaignId + '?limit=' + String.valueOf(queryLimit) + '&offset=' + String.valueOf(queryOffset);
            request.setEndpoint(endpoint);

            // Test Method doesn't support call outs
            if (Test.isRunningTest()) {
                return;
            }

            HttpResponse response = http.send(request);

            if (response.getStatusCode() != 200) {

                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', '***** Vend_Sync_DeletedResults::execute - Exit: StatusCode != 200 for endpoint: ' + endpoint);
                break;
            }

            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            if (results == null) {
                break;
            }

            List<Object> submissions = (List<Object>) results.get('submissions');
            if (submissions == null  || submissions.size() <= 0) {
                break;
            }
            
            Integer syncIndex = 1;
            for (Object submission: submissions) {
                
                String JSONData = JSON.serialize(submission);
                Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(JSONData);
				if (srData == null) {
					String errorMessage = '*****Vend_Sync_DeletedResults::execute AddError: Malformed Data_JSON__c field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
				}

                if (srData.get('id') == null) {
                    String errorMessage = '*****Vend_Sync_DeletedResults::execute AddError: Malformed Data_JSON__c missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

                    continue;
                }
                String id = srData.get('id').toString();

                if (activeTeamResults.containsKey(id)) {
                    deletedResults.add(new SR_Result__c(
                        Id = activeTeamResults.get(id)));
                }

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_DeletedResults::execute - queryOffset: ' + queryOffset + ' queryLimit: ' + queryLimit + ' syncIndex: ' + syncIndex++ + ' id: ' + id);
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;
		}

        System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_DeletedResults::execute delete count: ' + deletedResults.size());
          
		if (!deletedResults.isEmpty()) {
			Database.DeleteResult[] results = Database.delete(deletedResults, false);
            Vend_Sync_SharedCode.ProcessDatabaseResults(results, 'Vend_Sync_DeletedResults::execute delete');
		}
    }

    global void finish(Database.BatchableContext info) {
    }
}
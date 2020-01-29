// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend_Sync_Results.srSyncWebsiteResults( new List<Id> { '701R00000008JS4' });
*/
//  3) click Execute

global class Vend_Sync_Results implements Database.Batchable<sObject>, Database.AllowsCallouts { 

    global String query;

    global Database.querylocator start(Database.BatchableContext BC) {
        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Results::start - query: ' + query);
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext info, List<sObject> scope) {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Results::execute - scope: ' + scope);

        List<Id> campaignIds = new List<Id>();
        for (sObject scopeRecord :scope) {
            campaignIds.add(((Campaign)scopeRecord).Id);
        }

		if (campaignIds.isEmpty()) {
            String errorMessage = '***** Vend_Sync_Results::execute - No Active Campaign';
            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

			return;
        }

        String campaignId = String.valueOf(campaignIds[0]);
        this.SyncWebsiteResults(campaignId);
    }

    public void SyncWebsiteResults(String campaignId) {    

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody('{"token":"' + Vend_Sync_SharedCode.GetExternalWebsiteToken() + '"}');

		List<SR_Result__c> insertResults = new List<SR_Result__c>();
		Map<Id, SR_Result__c> updateResults = new Map<Id, SR_Result__c>();

        Integer queryOffset = 0;
        Integer queryLimit = 100;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 1;
        }

        Map<String, SR_Team__c> activeTeams = Vend_Sync_SharedCode.GetActiveTeams(false, campaignId, String.valueOf(this).substring(0,String.valueOf(this).indexOf(':')));
        Map<String,Id> activeTeamResults = Vend_Sync_SharedCode.GetActiveTeamResults(campaignId, String.valueOf(this).substring(0,String.valueOf(this).indexOf(':')));

        while (true) {
            
            String endpoint = 'https://' + Vend_Sync_SharedCode.GetExternalWebsiteSubdomain() + '.studentsrebuild.org/sync/submissions/' + campaignId + '?limit=' + String.valueOf(queryLimit) + '&offset=' + String.valueOf(queryOffset);
            request.setEndpoint(endpoint);

            // Test Method doesn't support call outs
            if (Test.isRunningTest()) {
                return;
            }

            HttpResponse response = http.send(request);

            if (response.getStatusCode() != 200) {

                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', '***** Vend_Sync_Results::execute - Exit: StatusCode != 200 for endpoint: ' + endpoint);
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
            for (Object result: submissions) {

                String JSONData = JSON.serialize(result);
                Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(JSONData);
				if (srData == null) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Malformed Data_JSON__c field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
				}

                SR_Result__c srResultObject = new SR_Result__c();

                // Check for submitted result
                if (srData.get('submittedAt') == null) {
					continue;
                }
                srResultObject.Submitted_Date__c = DateTime.valueOf(srData.get('submittedAt'));

                if (srData.get('id') == null) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Malformed Data_JSON__c missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
                }
                srResultObject.SR_External_ID__c = srData.get('id').toString();

                if (srData.get('teamId') == null) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Malformed Data_JSON__c missing teamId field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
                }
                String teamId = srData.get('teamId').toString();

                if (!activeTeams.containsKey(teamId)) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Salesforce missing team - SR_External_ID__c: ' + teamId;
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
                }
                srResultObject.SR_Team__c = activeTeams.get(teamId).Id;

                if (srData.get('itemCount') == null) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Malformed Data_JSON__c missing itemCount field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
                }
                srResultObject.SR_Number_of_Items__c = (Integer)srData.get('itemCount');

                if (srData.get('youngPeopleCount') == null) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Malformed Data_JSON__c missing youngPeopleCount field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
                }
                srResultObject.SR_Number_of_Young_People__c = (Integer)srData.get('youngPeopleCount');

                if (srData.get('isPhysical') == null) {
					String errorMessage = '*****Vend_Sync_Results::srSyncResults AddError: Malformed Data_JSON__c missing isPhysical field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

					continue;
                }
                srResultObject.Digital_Content_Url__c = (Boolean)srData.get('isPhysical') ? '' : 'Digital Content';

                if (activeTeamResults.containsKey(srResultObject.SR_External_ID__c)) {
                    srResultObject.Id = activeTeamResults.get(srResultObject.SR_External_ID__c);
                    updateResults.put(srResultObject.Id, srResultObject);
                }
                else {
                    srResultObject.Name = srResultObject.Submitted_Date__c.format();
                    insertResults.add(srResultObject);
                }

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Results::execute - queryOffset: ' + queryOffset + ' queryLimit: ' + queryLimit + ' syncIndex: ' + syncIndex++ + ' teamId: ' + teamId);
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;
		}

        System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Results::execute update count: ' + updateResults.size() + ' insert count: ' + insertResults.size());

		if (!updateResults.isEmpty()) {
			Database.SaveResult[] results = Database.update(updateResults.values(), false);
            Vend_Sync_SharedCode.ProcessDatabaseResults(results, 'Vend_Sync_Results::execute update');
		}

		if (!insertResults.isEmpty()) {            
			Database.SaveResult[] results = Database.insert(insertResults, false);
            Vend_Sync_SharedCode.ProcessDatabaseResults(results, 'Vend_Sync_Results::execute insert');
		}
    }

    global void finish(Database.BatchableContext info) {
    }
}
// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Students Rebuild: Hunger Challenge (Production)

    Developer Console (steps to call method directly)

        Vend_Sync_Teams.srSyncWebsiteTeams( new List<Id> { '7012I0000014IoB' });

*/
//  3) click Execute

global class Vend_Sync_Teams implements Database.Batchable<sObject>, Database.AllowsCallouts { 

    global String query;

    global Database.querylocator start(Database.BatchableContext BC) {
        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Teams::start - query: ' + query);
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext info, List<sObject> scope) {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Teams::execute - scope: ' + scope);

        List<Id> campaignIds = new List<Id>();
        for (sObject scopeRecord :scope) {
            campaignIds.add(((Campaign)scopeRecord).Id);
        }

		if (campaignIds.isEmpty()) {
            String errorMessage = '***** Vend_Sync_Teams::execute - No Active Campaign';
            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

			return;
        }

        String campaignId = String.valueOf(campaignIds[0]);
        this.SyncWebsiteTeams(campaignId);
    }

    public void SyncWebsiteTeams(String campaignId) {    

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody('{"token":"' + Vend_Sync_SharedCode.GetExternalWebsiteToken() + '"}');

        Integer queryOffset = 0;
        Integer queryLimit = 100;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 1;
        }

        Map<String, SR_Team__c> insertTeams = new Map<String, SR_Team__c>();
        Map<String, SR_Team__c> updateTeams = new Map<String, SR_Team__c>();

        Map<String, SR_Team__c> activeTeams = Vend_Sync_SharedCode.GetActiveTeams(true, campaignId, String.valueOf(this).substring(0,String.valueOf(this).indexOf(':')));

        while (true) {

            String endpoint = 'https://' + Vend_Sync_SharedCode.GetExternalWebsiteSubdomain() + '.studentsrebuild.org/sync/teams/' + campaignId + '?limit=' + String.valueOf(queryLimit) + '&offset=' + String.valueOf(queryOffset);
            request.setEndpoint(endpoint);

            // Test Method doesn't support call outs
            if (Test.isRunningTest()) {
                return;
            }

            HttpResponse response = http.send(request);

            if (response.getStatusCode() != 200) {

                if (queryOffset <= 0) {
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', '***** Vend_Sync_Teams::execute - Exit: StatusCode != 200 for endpoint: ' + endpoint   );
                }

                break;
            }

            Map<String, Object> resultsJSON = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            if (resultsJSON == null) {
                break;
            }

            List<Object> teams = (List<Object>) resultsJSON.get('teams');
            if (teams == null  || teams.size() <= 0) {
                break;
            }
            
            for (Object team: teams) {
                
                String JSONData = JSON.serialize(team);

                Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(JSONData);
                if (srData == null) {
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', '*****Vend_Sync_Teams::execute - Malformed Data_JSON__c field');
                    continue;
                }

                if (srData.get('id') == null) {
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', '*****Vend_Sync_Teams::execute - Malformed Data_JSON__c missing id field');
                    continue;
                }
                String id = srData.get('id').toString();

                if (srData.get('email') == null) {
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', '*****Vend_Sync_Teams::execute - Malformed Data_JSON__c missing email field');
                    continue;
                }
                String email = srData.get('email').toString();

                String uniqueId = email + campaignId + Id;
                if (activeTeams.containsKey(uniqueId)) {
                  
                    // Check if JSON String different than existing value on Team
                    SR_Team__c activeTeam = activeTeams.get(uniqueId);
                    if (activeTeam.Data_JSON__c.equalsIgnoreCase(JSONData)) {
                        continue;
                    }

                    updateTeams.put(
                        uniqueId,
                        new SR_Team__c(
                            Id = activeTeam.Id,
                            SR_External_ID__c = Id,
                            Unique_Id__c = uniqueId,
                            Data_JSON__c = JSONData));
                }
                else {

                    insertTeams.put(
                        uniqueId,
                        new SR_Team__c(
                            Name = 'Pending Registration',
                            Campaign__c = campaignId,
                            SR_External_ID__c = Id,
                            Unique_Id__c = uniqueId,
                            Data_JSON__c = JSONData));
                }
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;
        }

        System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Teams::execute update count: ' + updateTeams.size() + ' insert count: ' + insertTeams.size());

		if (!updateTeams.isEmpty()) {
			Database.SaveResult[] resultsUpdate = Database.update(updateTeams.values(), false);
            Vend_Sync_SharedCode.ProcessDatabaseResults(resultsUpdate, 'Vend_Sync_Teams::execute update');
		}

		if (!insertTeams.isEmpty()) {            
			Database.SaveResult[] resultsInsert = Database.insert(insertTeams.values(), false);
            Vend_Sync_SharedCode.ProcessDatabaseResults(resultsInsert, 'Vend_Sync_Teams::execute insert');
		}
    }

    global void finish(Database.BatchableContext info) {
    }
}
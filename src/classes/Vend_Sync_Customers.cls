// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend_Sync_Customers.srSyncWebsiteDeletedResults( new List<Id> { '701R00000008JS4' });
*/
//  3) click Execute

global class Vend_Sync_Customers { 

    @future (callout=true)
    public static void SyncVendCustomers_Future() {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Customers::SyncVendCustomers');

        Map<String, Vend_Customer__c> vendCustomers = new Map<String, Vend_Customer__c>();
        for (Vend_Customer__c vendCustomer :[SELECT Id__c FROM Vend_Customer__c]) {
            vendCustomers.put(vendCustomer.Id__c, vendCustomer);
        }

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + Vend_Sync_SharedCode.GetExternalWebsiteToken());
        request.setHeader('Content-Type', 'application/json');

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Customers::SyncVendCustomers request: ' + request);

		Map<String, Vend_Customer__c> updateCustomers = new Map<String, Vend_Customer__c>();
		Map<String, Vend_Customer__c> insertCustomers = new Map<String, Vend_Customer__c>();

        Integer queryOffset = 0;
        Integer queryLimit = 100;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 1;
        }

        while (true) {
            
            String endpoint = Vend_Sync_SharedCode.GetExternalWebsiteUrl() + 'customers?page_size=' + String.valueOf(queryLimit);
            request.setEndpoint(endpoint);

            // Test Method doesn't support call outs
            if (Test.isRunningTest()) {
                return;
            }

            HttpResponse response = http.send(request);

            if (response.getStatusCode() != 200) {

                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Vend Sync', '***** Vend_Sync_Customers::execute - Exit: StatusCode != 200 for endpoint: ' + endpoint);
                break;
            }

            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            if (results == null) {
                break;
            }

            List<Object> customers = (List<Object>) results.get('data');
            if (customers == null  || customers.size() <= 0) {
                break;
            }
            
            Integer syncIndex = 1;
            for (Object customer: customers) {
                
                String JSONData = JSON.serialize(customer);
                Map<String, Object> vendCustomer = (Map<String, Object>)JSON.deserializeUntyped(JSONData);
				if (vendCustomer == null) {
					String errorMessage = '*****Vend_Sync_Customers::execute AddError: Malformed JSON Data';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Vend Sync', errorMessage);

					continue;
				}

                if (vendCustomer.get('id') == null) {
                    String errorMessage = '*****Vend_Sync_Customers::execute AddError: Malformed JSON Data missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Vend Sync', errorMessage);

                    continue;
                }
                String id = vendCustomer.get('id').toString();

                if (vendCustomers.containsKey(id)) {
                    // Skip for now - need to check if need to clear the Contact_Updated__c
                    //  Maybe just update and if calls the trigger then in the trigger clear that flag
                    //  Make sure if no data changed that the trigger isn't call though
                }
                else {
                    insertCustomers.put(id, new Vend_Customer__c(Id__c = id));
                }

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Customers::execute - queryOffset: ' + queryOffset + ' queryLimit: ' + queryLimit + ' syncIndex: ' + syncIndex++ + ' id: ' + id);
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;

// DEBUG - kick out after 1 interation
            break;
		}

        System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Customers::execute update count: ' + updateCustomers.size() + ' insert count: ' + insertCustomers.size());
		if (!updateCustomers.isEmpty()) {

			Database.SaveResult[] saveResults = Database.update(updateCustomers.values(), false);
			for (Database.SaveResult result : saveResults) {
				if (!result.isSuccess()) {
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'BSP Admin', '*****Vend_Sync_Customers::execute Update ' + result.getErrors());
                    break;
                }
			}
		}

		if (!insertCustomers.isEmpty()) {  

			Database.SaveResult[] saveResults = Database.insert(insertCustomers.values(), false);
			for (Database.SaveResult result : saveResults) {
				if (!result.isSuccess()) {
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'BSP Admin', '*****Vend_Sync_Customers::execute Insert ' + result.getErrors());
                    break;
                }
			}
        }
    }
}
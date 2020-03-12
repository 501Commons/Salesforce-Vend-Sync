public class Vend_Sync_Object implements Queueable, Database.AllowsCallouts { 

    public enum VendApiTypes { customers, products, sales }
    public VendApiTypes vendApiType;
    public class InvalidParameterValueException extends Exception {}

    public void execute(QueueableContext context) {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Object::execute - vendApiType: ' + this.vendApiType.name());

        // Optimization Question? Can you use SObject instead of having 3 different sets of maps
        //
        Map<String, Vend_Customer__c> vendCustomers = new Map<String, Vend_Customer__c>();
        Map<String, Vend_Product__c> vendProducts = new Map<String, Vend_Product__c>();
        Map<String, Vend_Sale__c> vendSales = new Map<String, Vend_Sale__c>();

        switch on this.vendApiType {
            when customers {
                System.debug('****Vend_Sync_Object:execute - SOQL Query: SELECT id__c, updated_at__c FROM Vend_Customer__c');
                for (Vend_Customer__c customer :[SELECT id__c, updated_at__c FROM Vend_Customer__c]) {
                    vendCustomers.put(customer.id__c, customer);
                }
            }
            when products {
                System.debug('****Vend_Sync_Object:execute - SOQL Query: SELECT id__c, updated_at__c FROM Vend_Product__c');
                for (Vend_Product__c product :[SELECT id__c, updated_at__c FROM Vend_Product__c]) {
                    vendProducts.put(product.id__c, product);
                }
            }
            when sales {
                System.debug('****Vend_Sync_Object:execute - SOQL Query: SELECT id__c, updated_at__c FROM Vend_Sale__c');
                for (Vend_Sale__c sale :[SELECT id__c, updated_at__c FROM Vend_Sale__c]) {
                    vendSales.put(sale.id__c, sale);
                }
            }
        }

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + Vend_Sync_SharedCode.GetExternalWebsiteToken());
        request.setHeader('Content-Type', 'application/json');

        // Optimization Question? Can you use SObject instead of having 3 different sets of maps
        //
		Map<String, Vend_Customer__c> updateCustomers = new Map<String, Vend_Customer__c>();
		Map<String, Vend_Customer__c> insertCustomers = new Map<String, Vend_Customer__c>();
		Map<String, Vend_Product__c> updateProducts = new Map<String, Vend_Product__c>();
		Map<String, Vend_Product__c> insertProducts = new Map<String, Vend_Product__c>();
		Map<String, Vend_Sale__c> updateSales = new Map<String, Vend_Sale__c>();
		Map<String, Vend_Sale__c> insertSales = new Map<String, Vend_Sale__c>();

        Map<String, List<Object>> vendSaleLineItems = new Map<String, List<Object>>();

        Integer queryOffset = 0;
        Integer queryLimit = 200;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 200;
        }
        Long maxVersion = 0;
        Integer maxDMLQueueSize = 1000;

        Boolean singleInfoWritten = false;

        while (true) {
            
            String endpoint = Vend_Sync_SharedCode.GetExternalWebsiteUrl() + this.vendApiType.name() + '?page_size=' + String.valueOf(queryLimit) + (maxVersion > 0 ? '&after=' + String.valueOf(maxVersion) : '');
            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute - queryOffset: ' + queryOffset + ' queryLimit: ' + queryLimit + ' endpoint: ' + endpoint);
            request.setEndpoint(endpoint);

            // Test Method doesn't support call outs
            if (Test.isRunningTest()) {
                return;
            }

            HttpResponse response = http.send(request);

            if (response.getStatusCode() != 200) {

                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '***** Vend_Sync_Object::execute - Exit: StatusCode != 200 for endpoint: ' + endpoint);
                break;
            }

            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            if (results == null) {
                break;
            }

            Map<String, Object> vendVersions = (Map<String, Object>) results.get('version');
            if (vendVersions == null  || vendVersions.size() <= 0) {
                break;
            }

            // Check for max
            if (vendVersions.containsKey('max')) {
                maxVersion = (Long)vendVersions.get('max');
            }

            List<Object> vendObjects = (List<Object>) results.get('data');
            if (vendObjects == null  || vendObjects.size() <= 0) {
                break;
            }

            for (Object vendObject: vendObjects) {

                String JSONData = JSON.serialize(vendObject);

                if (!singleInfoWritten) {
                    singleInfoWritten = true;
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.INFO, Vend_Sync_SharedCode.ADMIN_TYPE, 'JSON Details for ' + this.vendApiType.name() + ' : ' + JSONData);
                }

                Map<String, Object> vendObjectMap = (Map<String, Object>)JSON.deserializeUntyped(JSONData);
				if (vendObjectMap == null) {
					String errorMessage = '*****Vend_Sync_Object::execute AddError: Malformed JSON data';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

					continue;
				}

                // Check for required fields
                //

                // Check for id
                if (vendObjectMap.get('id') == null) {
                    String errorMessage = '*****Vend_Sync_Object::execute AddError: Malformed JSON Data missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

                    continue;
                }
                String vend_id = String.valueOf(vendObjectMap.get('id'));

                // Check for updated_at
                if (vendObjectMap.get('updated_at') == null) {
                    String errorMessage = '*****Vend_Sync_Object::execute AddError: Malformed JSON Data missing updated_at field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

                    continue;
                }
                DateTime vend_updated_at = Datetime.valueOf(Vend_Sync_SharedCode.CleanVendJsonDateTime(String.valueOf(vendObjectMap.get('updated_at'))));

                switch on this.vendApiType {
                    when customers {

                        if (vendCustomers.containsKey(vend_id)) {
                            
                            if (vendCustomers.get(vend_id).updated_at__c <> vend_updated_at) {

                                Vend_Customer__c vendCustomer = new Vend_Customer__c(id__c = vend_id, updated_at__c = vend_updated_at);
                                Vend_Sync_Object.HandleObjectData((SObject)vendCustomer, vendObjectMap, Schema.SObjectType.Vend_Customer__c.fields.getMap());
        
                                vendCustomer.Id = vendCustomers.get(vend_id).Id;

                                // Field to signal the record has been changed
                                vendCustomer.Record_Reconciled__c = false;

                                updateCustomers.put(vend_id, vendCustomer);
                            }
                        }
                        else {
                            Vend_Customer__c vendCustomer = new Vend_Customer__c(id__c = vend_id, updated_at__c = vend_updated_at);
                            Vend_Sync_Object.HandleObjectData((SObject)vendCustomer, vendObjectMap, Schema.SObjectType.Vend_Customer__c.fields.getMap());

                            insertCustomers.put(vend_id, vendCustomer);
                        }
                    }
                    when products {

                        if (vendProducts.containsKey(vend_id)) {

                            if (vendProducts.get(vend_id).updated_at__c <> vend_updated_at) {

                                Vend_Product__c vendProduct = new Vend_Product__c(id__c = vend_id);
                                Vend_Sync_Object.HandleObjectData((SObject)vendProduct, vendObjectMap, Schema.SObjectType.Vend_Product__c.fields.getMap());
        
                                vendProduct.Id = vendProducts.get(vend_id).Id;

                                // Field to signal the record has been changed
                                vendProduct.Record_Reconciled__c = false;

                                updateProducts.put(vend_id, vendProduct);
                            }
                        }
                        else {
                            Vend_Product__c vendProduct = new Vend_Product__c(id__c = vend_id);
                            Vend_Sync_Object.HandleObjectData((SObject)vendProduct, vendObjectMap, Schema.SObjectType.Vend_Product__c.fields.getMap());

                            insertProducts.put(vend_id, vendProduct);
                        }
                    }
                    when sales {

                        Boolean processSaleRecord = false;
                        if (vendSales.containsKey(vend_id)) {

                            if (vendSales.get(vend_id).updated_at__c <> vend_updated_at) {

                                Vend_Sale__c vendSale = new Vend_Sale__c(id__c = vend_id);
                                Vend_Sync_Object.HandleObjectData((SObject)vendSale, vendObjectMap, Schema.SObjectType.Vend_Sale__c.fields.getMap());      
                                processSaleRecord = true;

                                vendSale.Id = vendSales.get(vend_id).Id;

                                // Field to signal the record has been changed
                                vendSale.Record_Reconciled__c = false;

                                updateSales.put(vend_id, vendSale);
                            }
                        }
                        else {
                            Vend_Sale__c vendSale = new Vend_Sale__c(id__c = vend_id);
                            Vend_Sync_Object.HandleObjectData((SObject)vendSale, vendObjectMap, Schema.SObjectType.Vend_Sale__c.fields.getMap());      
                            processSaleRecord = true;

                            insertSales.put(vend_id, vendSale);
                        }

                        if (processSaleRecord) {
                            // Store line_items
                            List<Object> vendSaleLineItemObjects = (List<Object>) vendObjectMap.get('line_items');
                            if (vendSaleLineItemObjects <> null && vendSaleLineItemObjects.size() > 0) {
                                vendSaleLineItems.put(vend_id, vendSaleLineItemObjects);
                            }
                        }
                    }
                }

                if (Test.isRunningTest()) {
                    break;
                }   
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;

            if (updateCustomers.size() > maxDMLQueueSize || insertCustomers.size() > maxDMLQueueSize ||
                updateProducts.size() > maxDMLQueueSize || insertProducts.size() > maxDMLQueueSize ||
                updateSales.size() > maxDMLQueueSize || insertSales.size() > maxDMLQueueSize ||
                vendSaleLineItems.size() > maxDMLQueueSize) {

                    System.debug('*****Vend_Sync_Object:execute Queue Size Exceeded so kick out and process, create more items on next sync');
                    break;
                }
		}

        switch on this.vendApiType {
            when customers {

                if (!updateCustomers.isEmpty()) {

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + this.vendApiType.name() + ' update count: ' + updateCustomers.size());
                    Database.SaveResult[] saveResults = Database.update(updateCustomers.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertCustomers.isEmpty()) {  

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + this.vendApiType.name() + ' insert count: ' + insertCustomers.size());
                    Database.SaveResult[] saveResults = Database.insert(insertCustomers.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Insert ' + result.getErrors());
                            break;
                        }
                    }
                }
            }
            when products {

                if (!updateProducts.isEmpty()) {

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + this.vendApiType.name() + ' update count: ' + updateProducts.size());
                    Database.SaveResult[] saveResults = Database.update(updateProducts.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertProducts.isEmpty()) {  

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + this.vendApiType.name() + ' insert count: ' + insertProducts.size());
                    Database.SaveResult[] saveResults = Database.insert(insertProducts.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Insert ' + result.getErrors());
                            break;
                        }
                    }
                }
            }
            when sales {

                if (!updateSales.isEmpty()) {

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + this.vendApiType.name() + ' update count: ' + updateSales.size());
                    Database.SaveResult[] saveResults = Database.update(updateSales.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertSales.isEmpty()) {  

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + this.vendApiType.name() + ' insert count: ' + insertSales.size());
                    Database.SaveResult[] saveResults = Database.insert(insertSales.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Insert ' + result.getErrors());
                            break;
                        }
                    }
                }

                // Process Sales - line_items
                Vend_Sync_Object.ProcessSaleLineItems(vendSaleLineItems, updateSales, insertSales);
            }
        }

        // Flush Queues
        Vend_Sync_SharedCode.FlushAllQueues();
    }

    private static void ProcessSaleLineItems(Map<String, List<Object>> vendSaleLineItems, Map<String, Vend_Sale__c> updateSales, Map<String, Vend_Sale__c> insertSales) {

		List<Vend_Sale_Line_Item__c> insertSaleLineItems = new List<Vend_Sale_Line_Item__c>();

        Set<String> vendSaleLineItemIds = new Set<String>();
        System.debug('****Vend_Sync_Object:ProcessSaleLineItems - SOQL Query: SELECT id__c FROM Vend_Sale_Line_Item__c');
        for (Vend_Sale_Line_Item__c vendSaleLineItem :[SELECT id__c FROM Vend_Sale_Line_Item__c]) {
            vendSaleLineItemIds.add(vendSaleLineItem.id__c);
        }

        Boolean singleInfoWritten = false;

        for (String vendSaleId :vendSaleLineItems.keySet()) {
   
            String vendSaleSalesforceId = '';
            if (updateSales.containsKey(vendSaleId)) {
                vendSaleSalesforceId = updateSales.get(vendSaleId).Id;
            }
            else if (insertSales.containsKey(vendSaleId)) {
                vendSaleSalesforceId = insertSales.get(vendSaleId).Id;
            }
            else {
                String errorMessage = '*****Vend_Sync_Object::ProcessSaleLineItems AddError: Missing Vend_Sale__c Salesforce Id for Master-Detail with Vend_Sale_Line_Item__c.Vend_Sale__c';
                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);
            }

            for (Object vendObject :vendSaleLineItems.get(vendSaleId)) {
            
                String JSONData = JSON.serialize(vendObject);

                if (!singleInfoWritten) {
                    singleInfoWritten = true;
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.INFO, Vend_Sync_SharedCode.ADMIN_TYPE, 'JSON Details for ProcessSaleLineItems : ' + JSONData);
                }
    
                Map<String, Object> vendObjectMap = (Map<String, Object>)JSON.deserializeUntyped(JSONData);

				if (vendObjectMap == null) {
					String errorMessage = '*****Vend_Sync_Object::ProcessSaleLineItems AddError: Malformed JSON Data';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

					continue;
				}

                // Check for required fields
                //

                // Check for id
                if (vendObjectMap.get('id') == null) {
                    String errorMessage = '*****Vend_Sync_Object::ProcessSaleLineItems AddError: Malformed JSON Data missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

                    continue;
                }
                String vend_id = String.valueOf(vendObjectMap.get('id'));

                // Check for sequence
                if (vendObjectMap.get('sequence') == null) {
                    String errorMessage = '*****Vend_Sync_Object::ProcessSaleLineItems AddError: Malformed JSON Data missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

                    continue;
                }
                String sequence = String.valueOf(vendObjectMap.get('sequence'));

                vend_id += sequence;
                if (vendSaleLineItemIds.contains(vend_id)) {
                    continue;
                }

                Vend_Sale_Line_Item__c vendSaleLineItem = new Vend_Sale_Line_Item__c(id__c = vend_id, Vend_Sale__c = vendSaleSalesforceId);
                Vend_Sync_Object.HandleObjectData((SObject)vendSaleLineItem, vendObjectMap, Schema.SObjectType.Vend_Sale_Line_Item__c.fields.getMap());
                insertSaleLineItems.add(vendSaleLineItem);
            }
        }

        if (!insertSaleLineItems.isEmpty()) {  

            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ProcessSaleLineItems insert count: ' + insertSaleLineItems.size());

            // Attempt insert and ignore errors - line items don't have an update_at field so don't know when they change.  Potentially could use the sales updated_at but for now just try to insert and
            //      let the DB block the insert if already in the DB
            Database.insert(insertSaleLineItems, false);
        }
    }

    private static Set<String> unhandledJsonFields = new Set<String>();
    private static String GetJSONField2String(String jsonField, Object jsonFieldObject) {

		if (jsonFieldObject == null) {
			return null;
		}
		else if (jsonFieldObject instanceOf String) {
			return String.valueOf(jsonFieldObject);
		}
		else if (jsonFieldObject instanceOf Boolean) {
			return Boolean.valueOf(jsonFieldObject) ? 'true' : 'false';
		}
		else if (jsonFieldObject instanceOf Integer) {
			return String.valueOf(Integer.valueOf(jsonFieldObject));
		}
		else if (jsonFieldObject instanceOf Double) {
			return String.valueOf(Double.valueOf(jsonFieldObject));
		}
		else {

            if (Vend_Sync_Object.unhandledJsonFields.contains(jsonField)) {
                return null;
            }

			String outputMessage = '*****Vend_Sync_Object::GetJSONField2String Unknown JSON Field Type for JSON Field: ' + jsonField + ' jsonFieldObject: ' + jsonFieldObject;
            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, outputMessage);
            
            Vend_Sync_Object.unhandledJsonFields.add(jsonField);
		}

		return null;
	}

	private static void HandleObjectData(SObject salesforceObject, Map<String, Object> jsonFields, Map<String, Schema.SObjectField> objectFields) {

		if (jsonFields.keySet().isEmpty() || objectFields.isEmpty()) {
			return;
		}

		for (String objectField :objectFields.keySet()) {

			try {

				String jsonField = objectField.removeEnd('__c');

				if (jsonFields.get(jsonField) != null) {

					Object jsonFieldObject = jsonFields.get(jsonField);

                    Schema.SObjectField f = objectFields.get(objectField);
                    Schema.DescribeFieldResult fResult = f.getDescribe();
                    
                    String jsonFieldStringValue = Vend_Sync_Object.GetJSONField2String(jsonField, jsonFieldObject);
                    if (String.isBlank(jsonFieldStringValue)) {
                        continue;
                    }

                    if (fResult.isUpdateable() && fResult.isAccessible()) {
                        if (fResult.getType() == Schema.DisplayType.STRING ||
                            fResult.getType() == Schema.DisplayType.EMAIL ||
                            fResult.getType() == Schema.DisplayType.PHONE ||
                            fResult.getType() == Schema.DisplayType.TEXTAREA ||
                            fResult.getType() == Schema.DisplayType.PICKLIST ||
                            fResult.getType() == Schema.DisplayType.MULTIPICKLIST) {

                            salesforceObject.put(objectField, jsonFieldStringValue);
                        }
                        else if (fResult.getType() == Schema.DisplayType.DOUBLE || fResult.getType() == Schema.DisplayType.INTEGER) {

                            salesforceObject.put(objectField, Integer.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.PERCENT) {

                            salesforceObject.put(objectField, Decimal.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.BOOLEAN) {

                            salesforceObject.put(objectField, Boolean.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.DATE) {

                            salesforceObject.put(objectField, Date.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.DATETIME) {

                            salesforceObject.put(objectField, Datetime.valueOf(Vend_Sync_SharedCode.CleanVendJsonDateTime(jsonFieldStringValue)));
                        }
                        else if (fResult.getType() == Schema.DisplayType.REFERENCE) {
                            continue;
                        }
                        else {
                            String outputMessage = '*****Vend_Sync_Object::HandleObjectData Error - Unknown Object Field Type: ' + fResult.getType() + ' objectField: ' + objectField;
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, outputMessage);
                        }
                    }
                }
			}
			catch(Exception e) {
				String outputMessage = '*****Vend_Sync_Object::HandleObjectData Exception: ' + Vend_Sync_SharedCode.GetExceptionMessage(e);
				Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, outputMessage);

				continue;
			}
		}
	}
}
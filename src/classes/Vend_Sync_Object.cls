// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend_Sync_Object.SyncVendObject_Future('vendObjects');
    Vend_Sync_Object.SyncVendObject_Future('products');
    Vend_Sync_Object.SyncVendObject_Future('products');
*/
//  3) click Execute

global class Vend_Sync_Object { 

    public enum VendApiTypes { customers, products, sales }
    public class InvalidParameterValueException extends Exception {}

    @future (callout=true)
    public static void SyncVendObject_Future(String vendApiTypeString) {

        if (String.isBlank(vendApiTypeString)) {
            throw new InvalidParameterValueException('Invalid vendApiTypeString is Null or Blank'); 
        }

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Object::SyncVendObject_Future - vendApiTypeString: ' + vendApiTypeString);

        Vend_Sync_Object.VendApiTypes vendApiType = Vend_Sync_Object.VendApiTypes.customers;
        if (Vend_Sync_Object.VendApiTypes.customers.name().equalsIgnoreCase(vendApiTypeString)) {
            vendApiType = Vend_Sync_Object.VendApiTypes.customers;
        }
        else if (Vend_Sync_Object.VendApiTypes.products.name().equalsIgnoreCase(vendApiTypeString)) {
            vendApiType = Vend_Sync_Object.VendApiTypes.products;
        }
        else if (Vend_Sync_Object.VendApiTypes.sales.name().equalsIgnoreCase(vendApiTypeString)) {
            vendApiType = Vend_Sync_Object.VendApiTypes.sales;
        }
        else {
            throw new InvalidParameterValueException('Invalid vendApiTypeString: ' + vendApiTypeString); 
        }

        // Optimization Question? Can you use SObject instead of having 3 different sets of maps
        //
        Map<String, Vend_Customer__c> vendCustomers = new Map<String, Vend_Customer__c>();
        Map<String, Vend_Product__c> vendProducts = new Map<String, Vend_Product__c>();
        Map<String, Vend_Sale__c> vendSales = new Map<String, Vend_Sale__c>();

        switch on vendApiType {
            when customers {
                for (Vend_Customer__c customer :[SELECT Id__c FROM Vend_Customer__c]) {
                    vendCustomers.put(customer.Id__c, customer);
                }
            }
            when products {
                for (Vend_Product__c product :[SELECT Id__c FROM Vend_Product__c]) {
                    vendProducts.put(product.Id__c, product);
                }
            }
            when sales {
                for (Vend_Sale__c sale :[SELECT Id__c FROM Vend_Sale__c]) {
                    vendSales.put(sale.Id__c, sale);
                }
            }
        }

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + Vend_Sync_SharedCode.GetExternalWebsiteToken());
        request.setHeader('Content-Type', 'application/json');

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Object::SyncVendObject_Future request: ' + request);

        // Optimization Question? Can you use SObject instead of having 3 different sets of maps
        //
		Map<String, Vend_Customer__c> updateCustomers = new Map<String, Vend_Customer__c>();
		Map<String, Vend_Customer__c> insertCustomers = new Map<String, Vend_Customer__c>();
		Map<String, Vend_Product__c> updateProducts = new Map<String, Vend_Product__c>();
		Map<String, Vend_Product__c> insertProducts = new Map<String, Vend_Product__c>();
		Map<String, Vend_Sale__c> updateSales = new Map<String, Vend_Sale__c>();
		Map<String, Vend_Sale__c> insertSales = new Map<String, Vend_Sale__c>();

        Integer queryOffset = 0;
        Integer queryLimit = 100;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 1;
        }

        while (true) {
            
            String endpoint = Vend_Sync_SharedCode.GetExternalWebsiteUrl() + vendApiType.name() + '?page_size=' + String.valueOf(queryLimit);
            request.setEndpoint(endpoint);

            // Test Method doesn't support call outs
            if (Test.isRunningTest()) {
                return;
            }

            HttpResponse response = http.send(request);

            if (response.getStatusCode() != 200) {

                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Vend Sync', '***** Vend_Sync_Object::execute - Exit: StatusCode != 200 for endpoint: ' + endpoint);
                break;
            }

            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            if (results == null) {
                break;
            }

            List<Object> vendObjects = (List<Object>) results.get('data');
            if (vendObjects == null  || vendObjects.size() <= 0) {
                break;
            }
            
            Integer syncIndex = 1;
            for (Object vendObject: vendObjects) {
                
                String JSONData = JSON.serialize(vendObject);
                Map<String, Object> vendObjectMap = (Map<String, Object>)JSON.deserializeUntyped(JSONData);
				if (vendObjectMap == null) {
					String errorMessage = '*****Vend_Sync_Object::execute AddError: Malformed JSON Data';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Vend Sync', errorMessage);

					continue;
				}

                if (vendObjectMap.get('id') == null) {
                    String errorMessage = '*****Vend_Sync_Object::execute AddError: Malformed JSON Data missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Vend Sync', errorMessage);

                    continue;
                }
                String id = vendObjectMap.get('id').toString();

                switch on vendApiType {
                    when customers {

                        Vend_Customer__c vendCustomer = new Vend_Customer__c(Id__c = id);
                        Vend_Sync_Object.HandleObjectData((SObject)vendCustomer, vendObjectMap, Schema.SObjectType.Vend_Customer__c.fields.getMap());

                        if (vendCustomers.containsKey(id)) {
                            // TBD - Add check to see if data changed then set the data change flag
                            vendCustomer.Id = vendCustomers.get(id).Id;
                            updateCustomers.put(id, (Vend_Customer__c)vendCustomer);
                        }
                        else {
                            insertCustomers.put(id, (Vend_Customer__c)vendCustomer);
                        }
                    }
                    when products {

                        Vend_Product__c vendProduct = new Vend_Product__c(Id__c = id);
                        Vend_Sync_Object.HandleObjectData((SObject)vendProduct, vendObjectMap, Schema.SObjectType.Vend_Product__c.fields.getMap());

                        if (vendProducts.containsKey(id)) {
                            // TBD - Add check to see if data changed then set the data change flag
                            //      Will need to update HandleObjectData to compare data so will need to build a query first so vendProducts has the data to compare against or can just use the trigger
                            vendProduct.Id = vendProducts.get(id).Id;
                            updateProducts.put(id, (Vend_Product__c)vendProduct);
                        }
                        else {
                            insertProducts.put(id, (Vend_Product__c)vendProduct);
                        }
                    }
                    when sales {

                        Vend_Sale__c vendSale = new Vend_Sale__c(Id__c = id);
                        Vend_Sync_Object.HandleObjectData((SObject)vendSale, vendObjectMap, Schema.SObjectType.Vend_Sale__c.fields.getMap());

                        if (vendSales.containsKey(id)) {
                            // TBD - Add check to see if data changed then set the data change flag
                            vendSale.Id = vendSales.get(id).Id;
                            updateSales.put(id, (Vend_Sale__c)vendSale);
                        }
                        else {
                            insertSales.put(id, (Vend_Sale__c)vendSale);
                        }
                    }
                }

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute - queryOffset: ' + queryOffset + ' queryLimit: ' + queryLimit + ' syncIndex: ' + syncIndex++ + ' id: ' + id);
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;

// DEBUG - kick out after 1 interation
            break;
		}

        switch on vendApiType {
            when customers {

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + vendApiType.name() + ' update count: ' + updateCustomers.size() + ' insert count: ' + insertCustomers.size());

                if (!updateCustomers.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.update(updateCustomers.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertCustomers.isEmpty()) {  
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

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + vendApiType.name() + ' update count: ' + updateProducts.size() + ' insert count: ' + insertProducts.size());

                if (!updateProducts.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.update(updateProducts.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertProducts.isEmpty()) {  
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

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::execute ' + vendApiType.name() + ' update count: ' + updateSales.size() + ' insert count: ' + insertSales.size());

                if (!updateSales.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.update(updateSales.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertSales.isEmpty()) {  
                    Database.SaveResult[] saveResults = Database.insert(insertSales.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::execute Insert ' + result.getErrors());
                            break;
                        }
                    }
                }
            }
        }
    }

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
			String outputMessage = '*****Vend_Sync_Object::GetJSONField2String Unknown JSON Field Type for JSON Field: ' + jsonField;
			Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, outputMessage);
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

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::HandleObjectData objectField: ' + objectField + ' fResult.getType(): ' + fResult.getType() + ' jsonFieldStringValue: ' + jsonFieldStringValue);

                    if (fResult.isUpdateable() && fResult.isAccessible()) {
                        if (fResult.getType() == Schema.DisplayType.STRING ||
                            fResult.getType() == Schema.DisplayType.EMAIL ||
                            fResult.getType() == Schema.DisplayType.PHONE ||
                            fResult.getType() == Schema.DisplayType.TEXTAREA ||
                            fResult.getType() == Schema.DisplayType.PICKLIST ||
                            fResult.getType() == Schema.DisplayType.MULTIPICKLIST) {

                            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::HandleObjectData put String salesforceObject: ' + salesforceObject);
                            salesforceObject.put(objectField, jsonFieldStringValue);
                        }
                        else if (fResult.getType() == Schema.DisplayType.DOUBLE || fResult.getType() == Schema.DisplayType.INTEGER) {

                            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::HandleObjectData put Double/Integer salesforceObject: ' + salesforceObject);
                            salesforceObject.put(objectField, Integer.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.BOOLEAN) {

                            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::HandleObjectData put Boolean salesforceObject: ' + salesforceObject);
                            salesforceObject.put(objectField, Boolean.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.DATE) {

                            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::HandleObjectData put Date salesforceObject: ' + salesforceObject);
                            salesforceObject.put(objectField, Date.valueOf(jsonFieldStringValue));
                        }
                        else if (fResult.getType() == Schema.DisplayType.REFERENCE) {
                            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::HandleObjectData put Reference (Ignore) salesforceObject: ' + salesforceObject);
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
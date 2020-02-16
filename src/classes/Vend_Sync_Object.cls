// Run Code FROM Developer Console
//  1) Debug -> Open SyncVendObject_Future Anonymous Window
//  2) paste code
/*
    Vend_Sync_Object.SyncVendObject_Future('customers');
    Vend_Sync_Object.SyncVendObject_Future('products');
    Vend_Sync_Object.SyncVendObject_Future('sales');
*/
//  3) click SyncVendObject_Future

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
                for (Vend_Customer__c customer :[SELECT id__c, updated_at__c FROM Vend_Customer__c]) {
                    vendCustomers.put(customer.id__c, customer);
                }
            }
            when products {
                for (Vend_Product__c product :[SELECT id__c, updated_at__c FROM Vend_Product__c]) {
                    vendProducts.put(product.id__c, product);
                }
            }
            when sales {
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
        Integer queryLimit = 100;
        if (Vend_Sync_SharedCode.IsSandbox) {
            queryLimit = 5;
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

                Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '***** Vend_Sync_Object::SyncVendObject_Future - Exit: StatusCode != 200 for endpoint: ' + endpoint);
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
					String errorMessage = '*****Vend_Sync_Object::SyncVendObject_Future AddError: Malformed JSON Data';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

					continue;
				}

                // Check for required fields
                //

                // Check for id
                if (vendObjectMap.get('id') == null) {
                    String errorMessage = '*****Vend_Sync_Object::SyncVendObject_Future AddError: Malformed JSON Data missing id field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

                    continue;
                }
                String vend_id = String.valueOf(vendObjectMap.get('id'));

                // Check for updated_at
                if (vendObjectMap.get('updated_at') == null) {
                    String errorMessage = '*****Vend_Sync_Object::SyncVendObject_Future AddError: Malformed JSON Data missing updated_at field';
                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);

                    continue;
                }
                DateTime vend_updated_at = Datetime.valueOf(Vend_Sync_SharedCode.CleanVendJsonDateTime(String.valueOf(vendObjectMap.get('updated_at'))));

                switch on vendApiType {
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

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::SyncVendObject_Future - queryOffset: ' + queryOffset + ' queryLimit: ' + queryLimit + ' syncIndex: ' + syncIndex++ + ' vend_id: ' + vend_id);
            }

            // Setup queryOffset for next collection
            queryOffset += queryLimit;

// DEBUG - kick out after 1 interation
            break;
		}

        switch on vendApiType {
            when customers {

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::SyncVendObject_Future ' + vendApiType.name() + ' update count: ' + updateCustomers.size() + ' insert count: ' + insertCustomers.size());

                if (!updateCustomers.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.update(updateCustomers.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::SyncVendObject_Future Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertCustomers.isEmpty()) {  
                    Database.SaveResult[] saveResults = Database.insert(insertCustomers.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::SyncVendObject_Future Insert ' + result.getErrors());
                            break;
                        }
                    }
                }
            }
            when products {

                System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::SyncVendObject_Future ' + vendApiType.name() + ' update count: ' + updateProducts.size() + ' insert count: ' + insertProducts.size());

                if (!updateProducts.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.update(updateProducts.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::SyncVendObject_Future Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertProducts.isEmpty()) {  
                    Database.SaveResult[] saveResults = Database.insert(insertProducts.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::SyncVendObject_Future Insert ' + result.getErrors());
                            break;
                        }
                    }
                }
            }
            when sales {

                if (!updateSales.isEmpty()) {

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::SyncVendObject_Future ' + vendApiType.name() + ' update count: ' + updateSales.size());
                    Database.SaveResult[] saveResults = Database.update(updateSales.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::SyncVendObject_Future Update ' + result.getErrors());
                            break;
                        }
                    }
                }
        
                if (!insertSales.isEmpty()) {  

                    System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::SyncVendObject_Future ' + vendApiType.name() + ' insert count: ' + insertSales.size());
                    Database.SaveResult[] saveResults = Database.insert(insertSales.values(), false);
                    for (Database.SaveResult result : saveResults) {
                        if (!result.isSuccess()) {
                            Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, '*****Vend_Sync_Object::SyncVendObject_Future Insert ' + result.getErrors());
                            break;
                        }
                    }
                }

                // Process Sales - line_items
                Vend_Sync_Object.ProcessSaleLineItems(vendSaleLineItems, updateSales, insertSales);
            }
        }
    }

    private static void ProcessSaleLineItems(Map<String, List<Object>> vendSaleLineItems, Map<String, Vend_Sale__c> updateSales, Map<String, Vend_Sale__c> insertSales) {

		List<Vend_Sale_Line_Item__c> insertSaleLineItems = new List<Vend_Sale_Line_Item__c>();

        Set<String> vendSaleLineItemIds = new Set<String>();
        for (Vend_Sale_Line_Item__c vendSaleLineItem :[SELECT id__c FROM Vend_Sale_Line_Item__c]) {
            vendSaleLineItemIds.add(vendSaleLineItem.id__c);
        }

        System.debug(LoggingLevel.DEBUG, '***** ProcessSaleLineItems vendSaleLineItemIds: ' + vendSaleLineItemIds);

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

            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Object::SyncVendObject_Future ProcessSaleLineItems insert count: ' + insertSaleLineItems.size());

            // Attempt insert and ignore errors - line items don't have an update_at field so don't know when they change.  Potentially could use the sales updated_at but for now just try to insert and
            //      let the DB block the insert if already in the DB
            Database.insert(insertSaleLineItems, false);
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
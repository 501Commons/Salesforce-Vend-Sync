@isTest
public with sharing class Vend_Sync_TriggerHelperTest {

	private static void setupTest() {
	}

	@isTest
	private static void batchTest() {

		Vend_Sync_TriggerHelperTest.setupTest();

		Vend_Sync_Batch.vendSyncBatch();

		Vend_Sync_Products syncProducts = new Vend_Sync_Products();
//		syncProducts.SyncVendCustomers();
		Vend_Sync_Sales syncSales = new Vend_Sync_Sales();
//		syncSales.SyncVendCustomers();
		Vend_Sync_Object syncCustomers = new Vend_Sync_Object();
//		syncCustomers.SyncVendCustomers();
	}

	@isTest
	private static void testInvalidParams()
	{
		Vend_Sync_TriggerHelper triggerHelper = new Vend_Sync_TriggerHelper();
		triggerHelper.updatevendCustomer(null, null, false);
		triggerHelper.updatevendCustomer(null, null, true);

		Vend_Customer__c vendCustomer = new Vend_Customer__c(
			Id__c = 'ExternalId'
		);
		database.insert(vendCustomer, false);
	}

	@isTest
	private static void testvendCustomerRegisterTestRecordTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		Vend_Customer__c vendCustomer = new Vend_Customer__c(
			Id__c = 'ExternalId'
		);

		//System.assertEquals(c_updates[0].LastName, contactData.get('lastName').toString());
		//System.assertEquals(c_updates[0].Email, srData.get('email').toString());

		// Check API Usage
		// ToDo
	}


	@isTest
	private static void testvendCustomerRegisterTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		Vend_Customer__c vendCustomer = new Vend_Customer__c(
			Id__c = 'ExternalId'
		);

		insert vendCustomer;

		// Check trigger
		List<Contact> c_updates = [select LastName, Email from Contact];
		//System.assert(!c_updates.isEmpty(), 'testvendCustomerRegisterTrigger - No Contact Created');

		//System.assertEquals(c_updates[0].LastName, contactData.get('lastName').toString());
		//System.assertEquals(c_updates[0].Email, srData.get('email').toString());

		// Check API Usage
		// ToDo
	}

	@isTest
	private static void testvendCustomerUpdateTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		Vend_Customer__c vendCustomer = new Vend_Customer__c(
			Id__c = 'ExternalId'
		);

		insert vendCustomer;

		// Call update to execute trigger
		update vendCustomer;

		// Check trigger results
		System.assertEquals('Updated', vendCustomer.Name);

		// Check API Usage
		// ToDo
	}
}
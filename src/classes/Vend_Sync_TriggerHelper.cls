public with sharing class Vend_Sync_TriggerHelper {

	public class InvalidParameterValueException extends Exception {}

	// only need one instance of this class per transaction
	private static Vend_Sync_TriggerHelper instance;
	public static Vend_Sync_TriggerHelper get() {
		if (instance == null) instance = new Vend_Sync_TriggerHelper();
		return instance;
	}

	public void updateVendCustomer( list<Vend_Customer__c> changedCustomers, map<id, Vend_Customer__c> oldMap, Boolean isAfter) {

		if (changedCustomers == null || changedCustomers.isEmpty()) {
			return;
		}
	}
}
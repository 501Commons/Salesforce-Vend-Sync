@isTest
public with sharing class Vend_Sync_TriggerHelperTest {

	private static void setupTest() {

		User Vend_Sync_TriggerHelperTestUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
		System.runAs(Vend_Sync_TriggerHelperTestUser) {

			EmailTemplate templateNew = new EmailTemplate(
				Name = 'SR_Web_Registration_New',
				DeveloperName = 'SR_Web_Registration_New',
				Body = 'Body',
				HtmlValue = '</br>',
				Subject = 'Subject',
				IsActive = true,
				FolderId = UserInfo.getUserId(),
				TemplateType = 'text'
			);
			insert templateNew;

			EmailTemplate templateExisting = new EmailTemplate(
				Name = 'SR_Web_Registration_Existing',
				DeveloperName = 'SR_Web_Registration_Existing',
				Body = 'Body',
				HtmlValue = '</br>',
				Subject = 'Subject',
				IsActive = true,
				FolderId = UserInfo.getUserId(),
				TemplateType = 'text'
			);
			insert templateExisting;

			Campaign campaignParent = new Campaign(
				Name = 'Students Rebuild - Parent',
				IsActive = true
			);

			insert campaignParent;

			Campaign campaignChild = new Campaign(
				Name = 'Students Rebuild - Child',
				IsActive = true,
				ParentId = campaignParent.Id
			);

			insert campaignChild;
		}
	}

	@isTest
	private static void batchTest() {

		Vend_Sync_TriggerHelperTest.setupTest();

		List<Campaign> campaigns = [Select Id From Campaign Where Name = 'Students Rebuild - Child'];
		Vend_Sync_Batch.srSyncWebsiteBatch(new List<Id> { campaigns[0].Id });

		Vend_Sync_Teams syncTeam = new Vend_Sync_Teams();
		syncTeam.SyncWebsiteTeams(campaigns[0].Id);
		Vend_Sync_Results syncResults = new Vend_Sync_Results();
		syncResults.SyncWebsiteResults(campaigns[0].Id);
		Vend_Sync_DeletedTeams deletedTeams = new Vend_Sync_DeletedTeams();
		deletedTeams.SyncWebsiteDeletedTeams(campaigns[0].Id);
		Vend_Sync_DeletedResults deletedResults = new Vend_Sync_DeletedResults();
		deletedResults.SyncWebsiteDeletedResults(campaigns[0].Id);
	}

	@isTest
	private static void testInvalidParams()
	{
		Vend_Sync_TriggerHelper triggerHelper = new Vend_Sync_TriggerHelper();
		triggerHelper.updateSRResult(null, null, false);
		triggerHelper.updateSRTeam(null, null, false);
		triggerHelper.updateSRTeam(null, null, true);

		SR_Team__c srTeam = new SR_Team__c(
			Name = 'SR_Team__c.Name',
			SR_External_ID__c = 'ExternalId',
			Unique_Id__c = 'UniqueId'
		);
		database.insert(srTeam, false);

		srTeam.Data_JSON__c = 
			'{' +
				'"notvalid":"notvalid"' +
			'}';
		database.insert(srTeam, false);

		srTeam.Data_JSON__c = 
			'{' +
				'"email":"db.bff@501commons.org"' +
			'}';
		database.insert(srTeam, false);

		srTeam.Data_JSON__c = 
			'{' +
				'"email":"db.bff@501commons.org"' +
				'"contact":{"firstName":"db.bff","lastName":"501Commons","role":"Other","age":"Over 65","roleOther":"Non-Standard Role"},' +
			'}';
		database.insert(srTeam, false);

		srTeam.Data_JSON__c = 
			'{' +
				'"email":"db.bff@501commons.org"' +
				'"contact":{"firstName":"db.bff","lastName":"501Commons","role":"Other","age":"Over 65","roleOther":"Non-Standard Role"},' +
				'"organization":{"name":"Example Organization","type":"Education/School","subtype":"Elementary"},"updatedAt":1536943856920,"ageGroups":["0-5"],"previouslyRegistered",false,"id":"5c4bbb36-a1a2-40ad-885a-e4ef4071f323"' +
			'}';
		database.insert(srTeam, false);

		srTeam.Data_JSON__c = 
			'{' +
				'"email":"db.bff@501commons.org"' +
				'"contact":{"firstName":"db.bff","lastName":"501Commons","role":"Other","age":"Over 65","roleOther":"Non-Standard Role"},' +
				'"organization":{"name":"Example Organization","type":"Education/School","subtype":"Elementary"},"updatedAt":1536943856920,"ageGroups":["0-5"],"previouslyRegistered",false,"id":"5c4bbb36-a1a2-40ad-885a-e4ef4071f323"' +
				'"location":{"country":"US","address":"24 Willie Mays Plaza","city":"San Francisco","postalCode":"94107","lon":-122.39081,"state":"California","lat":37.77813}' +
			'}';
		database.insert(srTeam, false);
	}

	@isTest
	private static void testSRTeamRegisterTestRecordTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		SR_Team__c srTeam = new SR_Team__c(
			Name = 'SR_Team__c.Name',
			SR_External_ID__c = 'ExternalId',
			Unique_Id__c = 'UniqueId'
		);

		srTeam.Data_JSON__c = 
			'{"location":{"country":"Gibraltar","address":"Keeling Summit","state":"Indiana","city":"Bayerfort","postalCode":"23863"},"lastSyncAt":1536877979609,"challengeId":"challengIdTestData","howDidYouHear":"At an Event","howDidYouHearOther":"Other Text","contact":{"firstName":"Dave","lastName":"Boyce","role":"Other","roleOther":"Other Role","age":"13-18"},"signUpForNewsletter":false,"registered":true,"email":"db.bff@501commons.org","name":"Changed Team 4","salesforceId":"a0Z4D000000c91hUAA","imageUrl":"https://something.org/newImage5.jpg","organization":{"name":"org dboyceman Test Record","type":"Community-Based Organization","subtype":"Other CBO","subtypeOther":"Other Subtype"},"updatedAt":1536877979609,"ageGroups":["18+"],"id":"testid","previouslyRegistered":true,"imageUrlApproved":false,"mapDisplayOptOut":false,"isTestRecord":true}';

		insert srTeam;

		// Check trigger results
		List<Contact> c_updates = [select LastName, Email from Contact];
		//System.assert(!c_updates.isEmpty(), 'testSRTeamRegisterTrigger - No Contact Created');

		Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(srTeam.Data_JSON__c);
		Map<String, Object> contactData = (Map<String, Object>)srData.get('contact');

		//System.assertEquals(c_updates[0].LastName, contactData.get('lastName').toString());
		//System.assertEquals(c_updates[0].Email, srData.get('email').toString());

		// Check API Usage
		// ToDo
	}


	@isTest
	private static void testSRTeamRegisterTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		SR_Team__c srTeam = new SR_Team__c(
			Name = 'SR_Team__c.Name',
			SR_External_ID__c = 'ExternalId',
			Unique_Id__c = 'UniqueId'
		);

		srTeam.Data_JSON__c = 
			'{"location":{"country":"Gibraltar","address":"Keeling Summit","state":"Indiana","city":"Bayerfort","postalCode":"23863"},"lastSyncAt":1536877979609,"challengeId":"challengIdTestData","howDidYouHear":"At an Event","howDidYouHearOther":"Other Text","contact":{"firstName":"Dave","lastName":"Boyce","role":"Other","roleOther":"Other Role","age":"13-18"},"signUpForNewsletter":false,"registered":true,"email":"db.bff@501commons.org","name":"Changed Team 4","salesforceId":"a0Z4D000000c91hUAA","imageUrl":"https://something.org/newImage5.jpg","organization":{"name":"org dboyceman","type":"Community-Based Organization","subtype":"Other CBO","subtypeOther":"Other Subtype"},"updatedAt":1536877979609,"ageGroups":["18+"],"id":"testid","previouslyRegistered":true,"imageUrlApproved":false,"mapDisplayOptOut":false}';

		insert srTeam;

		// Check trigger results
		List<Contact> c_updates = [select LastName, Email from Contact];
		//System.assert(!c_updates.isEmpty(), 'testSRTeamRegisterTrigger - No Contact Created');

		Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(srTeam.Data_JSON__c);
		Map<String, Object> contactData = (Map<String, Object>)srData.get('contact');

		//System.assertEquals(c_updates[0].LastName, contactData.get('lastName').toString());
		//System.assertEquals(c_updates[0].Email, srData.get('email').toString());

		// Check API Usage
		// ToDo
	}

	@isTest
	private static void testSRTeamUpdateTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		SR_Team__c srTeam = new SR_Team__c(
			Name = 'SR_Team__c.Name',
			SR_External_ID__c = 'ExternalId',
			Unique_Id__c = 'UniqueId'
		);

		srTeam.Data_JSON__c = 
			'{"location":{"country":"Gibraltar","address":"Keeling Summit","state":"Indiana","city":"Bayerfort","postalCode":"23863"},"lastSyncAt":1536877979609,"challengeId":"challengIdTestData","howDidYouHear":"At an Event","howDidYouHearOther":"Other Text","contact":{"firstName":"Dave","lastName":"Boyce","role":"Other","roleOther":"Other Role","age":"13-18"},"signUpForNewsletter":false,"registered":true,"email":"db.bff@501commons.org","name":"Changed Team 4","salesforceId":"a0Z4D000000c91hUAA","imageUrl":"https://something.org/newImage5.jpg","organization":{"name":"org dboyceman","type":"Community-Based Organization","subtype":"Other CBO","subtypeOther":"Other Subtype"},"updatedAt":1536877979609,"ageGroups":["18+"],"id":"testid","previouslyRegistered":true,"imageUrlApproved":false,"mapDisplayOptOut":false}';

		insert srTeam;

		// Call update to execute trigger
		srTeam.Name = 'Updated';
		update srTeam;

		// Check trigger results
		System.assertEquals('Updated', srTeam.Name);

		// Check API Usage
		// ToDo
	}

	@isTest
	private static void testSRResultTrigger() {

		Vend_Sync_TriggerHelperTest.setupTest();

		List<Campaign> campaigns = new List<Campaign>();
		campaigns = [Select Id From Campaign Where Name = 'Students Rebuild - Child'];

		Contact contact = new Contact(
			LastName = 'LastName',
			Email = 'email@email.com'
		);

		insert contact;

		Account organization = new Account(
			Name = 'Organization'
		);

		insert organization;

		SR_Team__c srTeam = new SR_Team__c(
			Name = 'SR_Team__c.Name',
			Leader__c = contact.Id,
			Organization__c = organization.Id,
			Campaign__c = campaigns[0].Id,
			SR_External_ID__c = contact.Id,
			Unique_Id__c = contact.Id
		);

		srTeam.Data_JSON__c = 
			'{"location":{"country":"Gibraltar","address":"Keeling Summit","state":"Indiana","city":"Bayerfort","postalCode":"23863"},"lastSyncAt":1536877979609,"challengeId":"challengIdTestData","howDidYouHear":"At an Event","howDidYouHearOther":"Other Text","contact":{"firstName":"Dave","lastName":"Boyce","role":"Other","roleOther":"Other Role","age":"13-18"},"signUpForNewsletter":false,"registered":true,"email":"db.bff@501commons.org","name":"Changed Team 4","salesforceId":"a0Z4D000000c91hUAA","imageUrl":"https://something.org/newImage5.jpg","organization":{"name":"org dboyceman","type":"Community-Based Organization","subtype":"Other CBO","subtypeOther":"Other Subtype"},"updatedAt":1536877979609,"ageGroups":["18+"],"id":"testid","previouslyRegistered":true,"imageUrlApproved":false,"mapDisplayOptOut":false}';

		insert srTeam;

		SR_Result__c srResult = new SR_Result__c(
			Name = 'SR_Result__c.Name',
			SR_Team__c = srTeam.Id,
			SR_Number_of_Items__c = 1,
			SR_Number_of_Young_People__c = 1
		);
		
		insert srResult;

		// Call update to execute trigger
		update srResult;

		// Check API Usage
		// ToDo
	}
}
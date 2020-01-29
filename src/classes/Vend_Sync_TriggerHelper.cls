public with sharing class Vend_Sync_TriggerHelper {

	public class InvalidParameterValueException extends Exception {}

	// only need one instance of this class per transaction
	private static Vend_Sync_TriggerHelper instance;
	public static Vend_Sync_TriggerHelper get() {
		if (instance == null) instance = new Vend_Sync_TriggerHelper();
		return instance;
	}

	public void updateSRResult( list<SR_Result__c> srResultList, map<id, SR_Result__c> oldMap, Boolean isAfter) {

		// Make sure Email jobs are scheduled
		ScheduleEmailJobs(Vend_Sync_Batch_Email.class.getName());

		if (srResultList == null || srResultList.isEmpty()) {
			return;
		}

		//
		// Perform all SOQL Queries outside of loop to avoid Salesforce Governor Limits: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
		//

		Set<Id> teamIds = new Set<Id>();
		for ( SR_Result__c srResult :srResultList ) {
			teamIds.add(srResult.SR_Team__c);
		}

		Map<Id, SR_Team__c> teams = new Map<Id, SR_Team__c>();
		for(SR_Team__c team : [
			SELECT Id, Name, Campaign__c, Leader__c, Leader__r.FirstName, Leader__r.LastName,
				Leader__r.Email, Organization__c, Organization__r.Name, Data_JSON__c,
				Total_Number_of_Items__c, Total_Number_of_Young_People__c
			FROM SR_Team__c
			WHERE Id in :teamIds]) {
	       		teams.put(team.Id, team);
		}

		if (teams.isEmpty()) {
			return;
		}

		Map<Id, List<SR_Result__c>> results = new Map<Id, List<SR_Result__c>>();
		for(SR_Result__c result : [
			SELECT CreatedDate, SR_Number_of_Items__c, SR_Number_of_Young_People__c, SR_Team__c, Result_Approved__c
			FROM SR_Result__c
			WHERE SR_Team__c in :teamIds]) {
				if (results.containsKey(result.SR_Team__c)) {
					List<SR_Result__c> teamResults = results.remove(result.SR_Team__c);
					teamResults.add(result);
					results.put(result.SR_Team__c, teamResults);
				}
				else {
					results.put(result.SR_Team__c, new List<SR_Result__c> { result });
				}
		}

		// Update API Tracking
		//Vend_Sync_SharedCode.UpdateAPIUsage(srResultList.Size(), 0);

		// Setup post loop processing lists
		Set<Id> teamsUpdated = new Set<Id>();
		Map<Id, Contact> contactsUpdate = new Map<Id, Contact>();

		for ( SR_Result__c srResult :srResultList ) {

			if (!teams.containsKey(srResult.SR_Team__c)) {
				// Missing Team - this should never happen because SR_Result__c is a Master/Detail child relationship to team
				throw new InvalidParameterValueException('Missing team reference for srResult.SR_Team__c: ' + srResult.SR_Team__c);
			}

			SR_Team__c team = teams.get(srResult.SR_Team__c);

			try {
				teamsUpdated.add(srResult.SR_Team__c);

				if (!isAfter) {

					List<SR_Result__c> teamResults = new List<SR_Result__c>();
					if (results.containsKey(team.Id)) {
						teamResults = results.get(team.Id);
					}
					teamResults.add(srResult);

					Integer totalItems = 0, totalPeople = 0;
					String teamResultsSummary = '';
					for (SR_Result__c teamResult :teamResults) {

						totalItems += Integer.valueOf(teamResult.SR_Number_of_Items__c);
						totalPeople += Integer.valueOf(teamResult.SR_Number_of_Young_People__c);

						teamResultsSummary += ((teamResult.CreatedDate == null) ? system.now() : teamResult.CreatedDate)
						+ ', # Items:  '
						+ Integer.valueOf(teamResult.SR_Number_of_Items__c)
						+ ', # Young People: '
						+ Integer.valueOf(teamResult.SR_Number_of_Young_People__c)
						+ ((teamResult.Result_Approved__c) ? ', Approved' : '')
						+ '\n';
					}

					String formData = 'Unique Id to include when mailing items: ' + team.Leader__c + '\n' +
						team.Leader__r.FirstName + ' ' + team.Leader__r.LastName + '\n' +
						team.Leader__r.Email + '\n' +
						'Team: ' + team.Name + '\n' +
						'Organization: ' + team.Organization__r.Name + '\n' +
						'Total Items: ' + totalItems + '\n' +
						'Total Young People: ' + totalPeople + '\n' +
						'\n\n' +
						teamResultsSummary;

					if (!String.isEmpty(team.Leader__c)) {
						if (contactsUpdate.containsKey(team.Leader__c)) {
							contactsUpdate.Remove(team.Leader__c);
						}
						
						contactsUpdate.put(
							team.Leader__c,
							new Contact(
								Id = team.Leader__c,
								SR_FormData__c = formData
						));
					}

					// Automatically approve all results
					srResult.Result_Approved__c = true;
				}
			}
			catch (Exception e) {
                String errorMessage = '*****Vend_Sync_TriggerHelper::updateSRResult Exception: ' + Vend_Sync_SharedCode.GetExceptionMessage(e);
				Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

				continue;
			}
		}

		if (!contactsUpdate.isEmpty()) {
			Database.SaveResult[] updateResults = Database.update(contactsUpdate.values(), false);
		}

		// Update Campaign and Campaign Member Roll-up once all the results are processed
		if (isAfter) {

			// Get Team Counts
			AggregateResult[] groupedTeamResults = [
				SELECT
					Campaign__c,
					COUNT(Id)SR_Number_of_Teams__c
				FROM SR_Team__c 
				GROUP BY Campaign__c];

			Map<String,Integer> teamCountsByCampaign = new Map<String,Integer>();
			for (AggregateResult resultTeams :groupedTeamResults) {
				teamCountsByCampaign.put(
					(String)resultTeams.get('Campaign__c'),
					(resultTeams.get('SR_Number_of_Teams__c') != null) ? (Integer)resultTeams.get('SR_Number_of_Teams__c') : 0);
			}

			AggregateResult[] groupedResults = [
				SELECT
					SUM(SR_Number_of_Items__c)SR_Number_of_Items__c,
					SUM(SR_Number_of_Young_People__c)SR_Number_of_Young_People__c,
					SR_Team__r.Campaign__c
				FROM SR_Result__c 
				WHERE Result_Approved__c = True
				GROUP BY SR_Team__r.Campaign__c];

			if (!groupedResults.isEmpty()) {
				List<Campaign> campaigns = new List<Campaign>();
				for (AggregateResult result :groupedResults) {

					Integer teamCount = 0;
					String campaignId = (String)result.get('Campaign__c');
					if (teamCountsByCampaign.containsKey(campaignId)) {
						teamCount = teamCountsByCampaign.get(campaignId);
					}

					campaigns.add(new Campaign(
						Id = campaignId,
						SR_Number_of_Items__c = (result.get('SR_Number_of_Items__c') != null) ? (Decimal)result.get('SR_Number_of_Items__c') : 0,
						SR_Number_of_Young_People__c = (result.get('SR_Number_of_Young_People__c') != null) ? (Decimal)result.get('SR_Number_of_Young_People__c') : 0,
						SR_Number_of_Teams__c = teamCount
					));
				}

				if (!campaigns.isEmpty()) {
					Database.SaveResult[] updateResults = Database.update(campaigns, false);
				}
			}
		}
	}

	public void updateSRTeam( list<SR_Team__c> srTeamList, map<id, SR_Team__c> oldMap, Boolean isAfter ) {

		if (srTeamList == null || srTeamList.isEmpty()) {
			return;
		}

		System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_TriggerHelper::updateSRTeam Processing ' + srTeamList.size() + ' SR Teams');

		// Debug - Uncomment code to be able to update historical campaign data
/*		for ( SR_Team__c srTeam :srTeamList ) {
			if (!srTeam.Data_JSON__c.contains('challengIdTestData')) {
				return;
			}
		}
*/		
		List<Campaign> campaigns = [select Id from Campaign WHERE Name LIKE 'Students Rebuild%' AND IsActive = true AND ParentId != null order by CreatedDate desc];
		if (campaigns.isEmpty()) {
			throw new InvalidParameterValueException('Campaign Error - missing active Students Rebuild Campaign');
		}

		// Walk thru teams to build lists for SOQL queries
		Set<String> contactEmails = new Set<String>();
		Set<String> accountNames = new Set<String>();
		Set<Id> teamIds = new Set<Id>();
		for (SR_Team__c srTeam :srTeamList) {

			// Check to make sure change related to the most recent and active campaign
			if (srTeam == null || (srTeam.Campaign__c != null && srTeam.Campaign__c != campaigns[0].Id)) {
				continue;
			}

			teamIds.add(srTeam.Id);

			try {
				// Data_JSON__c is set by the External WebServer
				if (String.isBlank(srTeam.Data_JSON__c)) {
					continue;
				}

				// Expand JSON data an check fields
				Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(srTeam.Data_JSON__c);
				if (srData == null) {
					String errorOutput = 'updateSRTeam::Error - Malformed Data_JSON__c field';
					System.debug(LoggingLevel.ERROR, '*****Vend_Sync_TriggerHelper::updateSRTeam ' + errorOutput);
					//srTeam.AddError(errorOutput);
					continue;
				}
				checkJSON(srData.get('email'), 'email');
				contactEmails.add(Vend_Sync_SharedCode.CleanEmailString(srData.get('email').toString(), true));

				Map<String, Object> orgData = (Map<String, Object>)srData.get('organization');
				if (orgData == null) {
					String errorOutput = 'updateSRTeam::Error - organization data is required in the Data_JSON__c field';
					System.debug(LoggingLevel.ERROR, '*****Vend_Sync_TriggerHelper::updateSRTeam ' + errorOutput);
					//srTeam.AddError(errorOutput);
					continue;
				}

				String orgName = orgData.get('name') != null ? Vend_Sync_SharedCode.CleanString(orgData.get('name').toString(), false) : 'Unknown';
				//checkJSON(orgData.get('name'), 'name');
				accountNames.add(orgName);
			}
			catch (Exception e) {
                String errorMessage = '*****Vend_Sync_TriggerHelper::updateSRTeam Exception: ' + Vend_Sync_SharedCode.GetExceptionMessage(e);
				Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

				continue;
			}
		}

		// Check if API triggered
		if (contactEmails.isEmpty() || accountNames.isEmpty()) {
			return;
		}

		if (!isAfter) {
			// Update API Tracking
			//Vend_Sync_SharedCode.UpdateAPIUsage(srTeamList.Size(), 0);
		}

		//
		// Perform all SOQL Queries outside of loop to avoid Salesforce Governor Limits: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
		//
		Map<String, Id> mapAccounts = new Map<String, Id>();
		for(Account account : [
			SELECT Name, Id
			FROM Account
			WHERE Name in :accountNames order by CreatedDate desc]) {
				if (!mapAccounts.containsKey(account.Name)) {
	      			mapAccounts.put(account.Name, account.Id);
				}
		}
		Map<String, Id> mapContacts = new Map<String, Id>();
		for(Contact contact : [
			SELECT Email, Id
			FROM Contact
			WHERE Email in :contactEmails order by CreatedDate desc]) {
				if (!mapContacts.containsKey(Vend_Sync_SharedCode.CleanString(contact.Email, true))) {
        			mapContacts.put(Vend_Sync_SharedCode.CleanString(contact.Email, true), contact.Id);
				}
		}

		User[] users = [SELECT Id, Email from User WHERE Name = 'Students Rebuild'];
		// Debug - ToDo switch to Students Rebuild in production
		//User[] users = [SELECT Id, Email from User WHERE Name = '501 Commons'];

		String previouslyRegistered = 'SR User Previously Registered';
		Set<Id> adminTasks = new Set<Id>();
		for(Task task : [
			SELECT WhoId, Subject
			FROM Task
			WHERE Subject = :previouslyRegistered]) {
   				adminTasks.add(task.WhoId);
			}

		// Setup post loop processing lists
		Map<String, Account> accountsInsert = new Map<String, Account>();
		Map<Id, Task> tasksInsert = new Map<Id, Task>();
		Map<String, Contact> contactsUpdate = new Map<String, Contact>();

		// Loop - Update Team, Create Accounts, Update Contact
		//
		for ( SR_Team__c srTeam :srTeamList ) {

			// Check to make sure change related to the most recent and active campaign
			if (srTeam == null || (srTeam.Campaign__c != null && srTeam.Campaign__c != campaigns[0].Id)) {
				continue;
			}

			try {

				if (isAfter) {

					//
					// isAfter - all srTeam fields are readonly
					//

					if (!String.isEmpty(srTeam.Leader__c)) {
						if (contactsUpdate.containsKey(srTeam.Leader__c)) {
							contactsUpdate.Remove(srTeam.Leader__c);
						}
						
						contactsUpdate.put(
							srTeam.Leader__c,
							new Contact(
								Id = srTeam.Leader__c,
								SR_Active_Team__c = srTeam.Id
						));
					}

					if (srTeam.Previously_Registered__c) {

						if (!users.isEmpty() && !adminTasks.contains(srTeam.Leader__c)) {

							tasksInsert.put(
								srTeam.Leader__c,
								new Task(
									WhoId = srTeam.Leader__c,
									//WhatId = srTeam.Id,
									OwnerId = users[0].Id,
									Subject = previouslyRegistered,
									priority= 'Normal',
									status = 'Not Started',
									description = previouslyRegistered + ' so look for historical contact records to merge or update historical teams to point to new contact.'));
						}
					}

					continue;
				}

				// Expand JSON data and check fields
				Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(srTeam.Data_JSON__c);
				if (srData == null) {
					String errorOutput = 'updateSRTeam::Error - Malformed Data_JSON__c field';
					System.debug(LoggingLevel.ERROR, '*****Vend_Sync_TriggerHelper::updateSRTeam ' + errorOutput);
					//srTeam.AddError(errorOutput);
					continue;
				}

				//checkJSON(srData.get('name'), 'name');
				checkJSON(srData.get('email'), 'email');
				checkJSON(srData.get('signUpForNewsletter'), 'signUpForNewsletter');
				checkJSON(srData.get('ageGroups'), 'ageGroups');
				checkJSON(srData.get('previouslyRegistered'), 'previouslyRegistered');
				checkJSON(srData.get('mapDisplayOptOut'), 'mapDisplayOptOut');

				srTeam.Name = srData.get('name') == null ? 'Pending Registration' : srData.get('name').toString();
				Boolean isTestRecord = (srData.get('isTestRecord') != null);
				if (isTestRecord) {
					if (!srTeam.Name.contains('*Test Record*')) {
						srTeam.Name = '*Test Record* ' + srTeam.Name;
					}
				}

				if (srData.get('createdAt') <> null) {
					String dateYYYMMDD = String.valueOf(srData.get('createdAt')).split('T')[0];
					String[] dateParts = dateYYYMMDD.split('-');
					String dateMMDDYYYY = dateParts[1] + '/' + dateParts[2] + '/' + dateParts[0];
					srTeam.Registered_Date__c = Date.parse(dateMMDDYYYY);
				}

				srTeam.Registered__c = srData.get('registered') <> null ? Boolean.valueOf(srData.get('registered')) : false;

				Map<String, Object> contactData = (Map<String, Object>)srData.get('contact');
				if (contactData == null) {
					String errorOutput = 'updateSRTeam::Error - contact data is required in the Data_JSON__c field';
					System.debug(LoggingLevel.ERROR, '*****Vend_Sync_TriggerHelper::updateSRTeam ' + errorOutput);
					//srTeam.AddError(errorOutput);
					continue;
				}

				checkJSON(contactData.get('lastName'), 'lastName');
				checkJSON(contactData.get('firstName'), 'firstName');

				Map<String, Object> orgData = (Map<String, Object>)srData.get('organization');
				String orgName = orgData.get('name') != null ? Vend_Sync_SharedCode.CleanString(orgData.get('name').toString(), false) : 'Unknown';
				//checkJSON(orgData.get('name'), 'name');

				//checkJSON(orgData.get('type'), 'type');
				//checkJSON(orgData.get('subtype'), 'subtype');

				Map<String, Object> locationData = (Map<String, Object>)srData.get('location');
				if (locationData == null) {
					String errorOutput = 'updateSRTeam::Error - location data is required in the Data_JSON__c field';
					System.debug(LoggingLevel.ERROR, '*****Vend_Sync_TriggerHelper::updateSRTeam ' + errorOutput);
					//srTeam.AddError(errorOutput);
					continue;
				}

				//checkJSON(locationData.get('country'), 'country');
				//checkJSON(locationData.get('state'), 'state');
				//checkJSON(locationData.get('city'), 'city');
				//checkJSON(locationData.get('address'), 'address');
				//checkJSON(locationData.get('postalCode'), 'postalCode');

				// Organization
				Account account = new Account();

				if (orgData.get('type') != null && orgData.get('subtype') != null) {
					String orgType = orgData.get('type').toString();
					String orgSubType = orgData.get('subtype').toString();
					if (!String.isBlank(orgType) && !String.isBlank(orgSubType) && (orgType == 'Community-Based Organization' || orgType == 'Education/School' || orgType == 'Individual/Family' || orgType == 'Other')) {
						account.Org_Type__c = orgType;

						if (orgType == 'Community-Based Organization' && (orgSubType == 'Faith-based' || orgSubType == 'Library' || orgSubType == 'Museum' || orgSubType == 'Other CBO' || orgSubType == 'Service or volunteer club' || orgSubType == 'Youth and Families')) {
							account.Org_Sub_Type__c = orgSubType;
						}
						if (orgType == 'Education/School' && (orgSubType == 'College/University' || orgSubType == 'Early childhood 0-5' || orgSubType == 'Elementary' || orgSubType == 'High School' || orgSubType == 'Jr. High/Middle' || orgSubType == 'Other Education/School' || orgSubType == 'Out of school program' || orgSubType == 'School District' || orgSubType == 'School Library')) {
							account.Org_Sub_Type__c = orgSubType;
						}
						if (orgType == 'Individual/Family' && orgSubType == 'Individual/Family') {
							account.Org_Sub_Type__c = orgSubType;
						}
						if (orgType == 'Other' && orgSubType == 'Other') {
							account.Org_Sub_Type__c = orgSubType;
							account.Org_Type_Other__c = orgData.get('subtypeOther') != null ? orgData.get('subtypeOther').toString() : '';
						}
					}
				}

				if (locationData.get('address') != null && !String.isBlank(locationData.get('address').toString())) {
					account.BillingStreet = locationData.get('address').toString();
				}
				if (locationData.get('city') != null && !String.isBlank(locationData.get('city').toString())) {
					account.BillingCity = locationData.get('city').toString();
				}
				if (locationData.get('state') != null && !String.isBlank(locationData.get('state').toString())) {
					account.BillingState = locationData.get('state').toString();
				}
				if (locationData.get('postalCode') != null && !String.isBlank(locationData.get('postalCode').toString())) {
					account.BillingPostalCode = locationData.get('postalCode').toString();
				}
				if (locationData.get('country') != null && !String.isBlank(locationData.get('country').toString())) {
					account.BillingCountry = locationData.get('country').toString();
				}
				
				account.Name = Vend_Sync_SharedCode.CleanString(orgName, false);
				if (!mapAccounts.containsKey(account.Name)) {

					accountsInsert.put(
						account.Name,
						account);
				}

				// Update SR Team fields
				if (srTeam.Campaign__c == null || String.isBlank(srTeam.Campaign__c)) {
					srTeam.Campaign__c = campaigns[0].Id;
				}
				List<Object> ageGroups = (List<Object>)srData.get('ageGroups');
				srTeam.SR_Age_Range_0_5_years_old__c = ageGroups.contains('0-5');
				srTeam.SR_Age_Range_6_11_years_old__c = ageGroups.contains('6-11');
				srTeam.SR_Age_Range_12_14_years_old__c = ageGroups.contains('12-14');
				srTeam.SR_Age_Range_15_17_years_old__c = ageGroups.contains('15-17');
				srTeam.SR_Age_Range_18_years_old__c = (ageGroups.contains('Over 18') || ageGroups.contains('18+'));

				if (srData.get('howDidYouHear') != null) {
					srTeam.Hear_About__c = srData.get('howDidYouHear').toString();
				}
				srTeam.Hear_About_Other__c = srData.get('howDidYouHearOther') != null ? srData.get('howDidYouHearOther').toString().left(64) : '';
				if (contactData.get('role') != null) {
					srTeam.Team_Leader_Role__c = contactData.get('role').toString();
				}
				srTeam.Team_Leader_Role_Other__c = contactData.get('roleOther') != null ? contactData.get('roleOther').toString().left(64) : '';
				if (contactData.get('age') != null) {
					srTeam.Team_Leader_Age__c = contactData.get('age').toString();
				}
				srTeam.Map_Display_OptOut__c = Boolean.valueOf(srData.get('mapDisplayOptOut'));
				srTeam.Previously_Registered__c = Boolean.valueOf(srData.get('previouslyRegistered'));
				srTeam.Image_Url__c = srData.get('imageUrl') != null ? srData.get('imageUrl').toString() : '';

				srTeam.Organization_Name__c = account.Name;
				srTeam.Street__c = account.BillingStreet;
				srTeam.City__c = account.BillingCity;
				srTeam.State__c = account.BillingState;
				srTeam.PostalCode__c = account.BillingPostalCode;
				srTeam.Country__c = account.BillingCountry;

				srTeam.Org_Type__c = account.Org_Type__c;
				srTeam.Org_Sub_Type__c = account.Org_Sub_Type__c;
				srTeam.Org_Type_Other__c = account.Org_Type_Other__c;

				// Optional Fields
				String approvedImageUrl = (srData.get('approvedImageUrl') != null) ? srData.get('approvedImageUrl').toString() : '';
				if (!String.isBlank(approvedImageUrl)) {
					srTeam.Image_Approved__c = true;
				} else {
					srTeam.Image_Approved__c = false;
				}
			}
			catch (Exception e) {
                String errorMessage = '*****Vend_Sync_TriggerHelper::updateSRTeam Exception: ' + Vend_Sync_SharedCode.GetExceptionMessage(e);
				Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

				continue;
			}
		}

		// Perform all DML (Data Manipulation Language) calls (insert, update, merge, delete, restore) outside of loop to avoid Salesforce Governor Limits: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
		if (!tasksInsert.isEmpty()) {
			insert tasksInsert.values();
		}
		if (!accountsInsert.isEmpty()) {
			List<Account> accountsToInsert = accountsInsert.values();
			insert accountsToInsert;

			for (Account account :accountsToInsert) {
				mapAccounts.put(account.Name, account.Id);
			}
		}

		if (isAfter) {

			if (!contactsUpdate.isEmpty()) {
				if (contactsUpdate.size() > 1) {
					Database.SaveResult[] results = Database.update(contactsUpdate.values(), false);
					Vend_Sync_SharedCode.ProcessDatabaseResults(results, 'Vend_Sync_Teams::execute update');
				}
				else {
					update contactsUpdate.values();
				}
			}

			return;
		}

		//
		// Perform all SOQL Queries outside of loop to avoid Salesforce Governor Limits: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
		//

		// Setup post loop processing lists
		Map<String, Contact> contactsInsert = new Map<String, Contact>();

		// Loop - Create/Update Contacts
		//
		for ( SR_Team__c srTeam :srTeamList ) {

			// Check to make sure change related to the most recent and active campaign
			if (srTeam == null || (srTeam.Campaign__c != null && srTeam.Campaign__c != campaigns[0].Id)) {
				continue;
			}

			try {
				Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(srTeam.Data_JSON__c);

				Map<String, Object> orgData = (Map<String, Object>)srData.get('organization');
				//checkJSON(orgData.get('name'), 'name');
				String orgName = orgData.get('name') != null ? Vend_Sync_SharedCode.CleanString(orgData.get('name').toString(), false) : 'Unknown';

				Map<String, Object> contactData = (Map<String, Object>)srData.get('contact');

				// Get Contact by Email
				Contact contact = new Contact(
					email = Vend_Sync_SharedCode.CleanEmailString(srData.get('email').toString(), true)
				);

				// Update Contact fields
				contact.SR_Email_Newsletter__c = Boolean.valueOf(srData.get('signUpForNewsletter'));
				contact.FirstName = contactData.get('firstName').toString();
				contact.LastName = contactData.get('lastName').toString();
				if (mapAccounts.containsKey(orgName)) {

					// Modifying AccountId will cause a new affiliation to get created while maintaining the previous account as the former affiliation
					contact.AccountId = mapAccounts.get(orgName);
				}

				if (!mapContacts.containsKey(contact.email)) {
					Boolean isTestRecord = (srData.get('isTestRecord') != null);
					if (isTestRecord) {
						contact.LastName = '*TestRecord* ' + contact.LastName;
					}

					contactsInsert.put(
						contact.email,
						contact);
				}
				else {
					srTeam.Returning_User__c = true;
					contact.Id = mapContacts.get(Vend_Sync_SharedCode.CleanEmailString(srData.get('email').toString(), true));
					contactsUpdate.put(
						contact.Id,
						contact);
				}

				srTeam.Organization__c = mapAccounts.get(orgName);
			}
			catch (Exception e) {
                String errorMessage = '*****Vend_Sync_TriggerHelper::updateSRTeam Exception: ' + Vend_Sync_SharedCode.GetExceptionMessage(e);
				Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

				continue;
			}
		}

		//
		// Perform all DML (Data Manipulation Language) calls (insert, update, merge, delete, restore) outside of loop to avoid Salesforce Governor Limits: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
		//
		if (!contactsInsert.isEmpty()) {
			insert contactsInsert.values();
		}
		if (!contactsUpdate.isEmpty()) {
			update contactsUpdate.values();
		}

		//
		// Perform all SOQL Queries outside of loop to avoid Salesforce Governor Limits: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
		//
		for(Contact contact : [
			SELECT Email, Id
			FROM Contact
			WHERE Email in :contactEmails order by LastModifiedDate desc]) {
        		mapContacts.put(Vend_Sync_SharedCode.CleanString(contact.Email, true), contact.Id);
		}

		// Loop - Update Team Leader
		//
		for ( SR_Team__c srTeam :srTeamList ) {

			// Check to make sure change related to the most recent and active campaign
			if (srTeam == null || (srTeam.Campaign__c != null && srTeam.Campaign__c != campaigns[0].Id)) {
				continue;
			}

			try {
				Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(srTeam.Data_JSON__c);
				if (!mapContacts.containsKey(Vend_Sync_SharedCode.CleanEmailString(srData.get('email').toString(), true))) {
					continue;
				}

				srTeam.Leader__c = mapContacts.get(Vend_Sync_SharedCode.CleanEmailString(srData.get('email').toString(), true));
				if (srTeam.Leader__c == null || String.isBlank(srTeam.Leader__c)) {
					continue;
				}

				// Welcome Emails sent via REST calls
				srTeam.Welcome_Email_Sent__c = true;
			}
			catch (Exception e) {
                String errorMessage = '*****Vend_Sync_TriggerHelper::updateSRTeam Exception: ' + Vend_Sync_SharedCode.GetExceptionMessage(e);
				Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, 'Students Rebuild', errorMessage);

				continue;
			}
		}
	}

	private void checkJSON(Object fieldReference, String fieldName)
	{
		if (fieldReference == null) {
			throw new InvalidParameterValueException('checkJSON Error - missing field: ' + fieldName);
		}
	}

    private void ScheduleEmailJobs(String scheduleName) {

        List<CronJobDetail> cronJobDetails = [SELECT Id, JobType, Name FROM CronJobDetail];
        Set<String> scheduledJobs = new Set<String>();
        for (CronJobDetail jobDetail :cronJobDetails) {

            scheduledJobs.add(jobDetail.Name);
        }

        // Offset Schedules so not running at the same time
        Integer minuteOffset = 0;
        if (scheduleName == Vend_Sync_TriggerHelper.class.getName()) {
            minuteOffset = 2; 
        }

        String cronExpression, scheduleJobName;
        Integer triggerNumber = 0;
        for (integer i = minuteOffset; i <= 59; i += 5) {
            cronExpression = '0 ' + String.valueOf(i) + ' * * * ?';
            scheduleJobName = scheduleName + '_' + (triggerNumber <= 9 ? '0' : '') + String.valueOf(triggerNumber++);

            if (scheduledJobs.contains(scheduleJobName)) {
                continue;
            }

            // Optimization for future since this is a only unique code - call out here to a Virtual function that can be overloaded from a child (e.g., SM Rules - Vend_Sync_SM_Rule_Contact_NameDOB)
            if (scheduleName == Vend_Sync_Batch_Email.class.getName()) {
                System.schedule(scheduleJobName, cronExpression, new Vend_Sync_Batch_Email());
            }
        }
    }
}